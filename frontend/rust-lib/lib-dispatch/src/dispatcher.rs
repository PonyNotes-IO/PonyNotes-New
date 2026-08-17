use derivative::*;
use pin_project::pin_project;
use std::any::Any;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};
use tracing::event;

use crate::module::AFPluginStateMap;
use crate::runtime::AFPluginRuntime;
use crate::{
  errors::{DispatchError, Error, InternalError},
  module::{plugin_map_or_crash, AFPlugin, AFPluginMap, AFPluginRequest},
  response::AFPluginEventResponse,
  service::{AFPluginServiceFactory, Service},
};

#[cfg(feature = "local_set")]
pub trait AFConcurrent: Send {}

#[cfg(feature = "local_set")]
impl<T> AFConcurrent for T where T: Send + ?Sized {}

#[cfg(not(feature = "local_set"))]
pub trait AFConcurrent: Send + Sync {}

#[cfg(not(feature = "local_set"))]
impl<T> AFConcurrent for T where T: Send + Sync {}

#[cfg(feature = "local_set")]
pub type AFBoxFuture<'a, T> = futures_core::future::LocalBoxFuture<'a, T>;

#[cfg(not(feature = "local_set"))]
pub type AFBoxFuture<'a, T> = futures_core::future::BoxFuture<'a, T>;

pub type AFStateMap = std::sync::Arc<AFPluginStateMap>;

#[cfg(feature = "local_set")]
pub(crate) fn downcast_owned<T: 'static>(boxed: AFBox) -> Option<T> {
  boxed.downcast().ok().map(|boxed| *boxed)
}

#[cfg(not(feature = "local_set"))]
pub(crate) fn downcast_owned<T: 'static + Send + Sync>(boxed: AFBox) -> Option<T> {
  boxed.downcast().ok().map(|boxed| *boxed)
}

#[cfg(feature = "local_set")]
pub(crate) type AFBox = Box<dyn Any + Send + Sync>;

#[cfg(not(feature = "local_set"))]
pub(crate) type AFBox = Box<dyn Any + Send + Sync>;

#[cfg(feature = "local_set")]
pub type BoxFutureCallback =
  Box<dyn FnOnce(AFPluginEventResponse) -> AFBoxFuture<'static, ()> + 'static>;

#[cfg(not(feature = "local_set"))]
pub type BoxFutureCallback =
  Box<dyn FnOnce(AFPluginEventResponse) -> AFBoxFuture<'static, ()> + Send + Sync + 'static>;

pub struct AFPluginDispatcher {
  plugins: AFPluginMap,
  #[allow(dead_code)]
  runtime: Arc<AFPluginRuntime>,
}

impl AFPluginDispatcher {
  pub fn new(runtime: Arc<AFPluginRuntime>, plugins: Vec<AFPlugin>) -> AFPluginDispatcher {
    tracing::trace!("{}", plugin_info(&plugins));
    AFPluginDispatcher {
      plugins: plugin_map_or_crash(plugins),
      runtime,
    }
  }

  #[cfg(feature = "local_set")]
  pub async fn async_send<Req>(dispatch: &AFPluginDispatcher, request: Req) -> AFPluginEventResponse
  where
    Req: Into<AFPluginRequest> + 'static,
  {
    AFPluginDispatcher::async_send_with_callback(dispatch, request, |_| Box::pin(async {})).await
  }
  #[cfg(feature = "local_set")]
  pub async fn async_send_with_callback<Req, Callback>(
    dispatch: &AFPluginDispatcher,
    request: Req,
    callback: Callback,
  ) -> AFPluginEventResponse
  where
    Req: Into<AFPluginRequest> + 'static,
    Callback: FnOnce(AFPluginEventResponse) -> AFBoxFuture<'static, ()> + AFConcurrent + 'static,
  {
    Self::boxed_async_send_with_callback(dispatch, request, callback).await
  }

  #[cfg(feature = "local_set")]
  pub async fn boxed_async_send_with_callback<Req, Callback>(
    dispatch: &AFPluginDispatcher,
    request: Req,
    callback: Callback,
  ) -> AFPluginEventResponse
  where
    Req: Into<AFPluginRequest> + 'static,
    Callback: FnOnce(AFPluginEventResponse) -> AFBoxFuture<'static, ()> + AFConcurrent + 'static,
  {
    let request: AFPluginRequest = request.into();
    let plugins = dispatch.plugins.clone();
    let service = Box::new(DispatchService { plugins });
    tracing::trace!("[dispatch]: Async event: {:?}", &request.event);
    // 事件名先留一份，超时诊断时要用（request 会被 move 进 service_ctx）。
    let event_for_diagnostics = format!("{:?}", &request.event);

    // 【2026-08-17 修复：上一轮的 60s 兜底其实救不了 Dart】
    //
    // 回调（post_to_flutter）是【唯一】把响应投递回 Dart 的途径，而它被 move 进
    // 了下面 spawn_local 的任务里，只有在 handler 正常跑完后才会被调用。
    // 上一轮超时分支只是 `return error.as_response()` —— 这个返回值交给
    // dart-ffi 的 Runner，而 FFI 路径调用 dispatch 时传的是 `ret: None`，
    // 于是这个错误响应被直接丢弃，Dart 侧的 Completer 依旧永远悬着。
    // 也就是说：兜底日志（还因为 lib_dispatch 未纳入日志过滤器而不可见）打了，
    // 但客户端该卡还是卡。
    //
    // 现在把回调放进一个「只允许取走一次」的格子里：handler 正常完成时由它取走，
    // 超时时由兜底分支取走。谁先取到谁负责投递，保证 Dart 侧恰好收到一次响应
    // ——正常响应或超时错误——绝不会一直悬着。
    // 本函数是 local_set 版本（单线程 LocalSet），故用 Rc<RefCell<_>> 即可，
    // BoxFutureCallback 在该 cfg 下也没有 Send 约束。
    let shared_callback: std::rc::Rc<std::cell::RefCell<Option<BoxFutureCallback>>> =
      std::rc::Rc::new(std::cell::RefCell::new(Some(Box::new(callback))));

    let handler_callback = shared_callback.clone();
    let once_callback: BoxFutureCallback = Box::new(move |resp: AFPluginEventResponse| {
      let taken = handler_callback.borrow_mut().take();
      Box::pin(async move {
        if let Some(cb) = taken {
          cb(resp).await;
        }
      })
    });

    let service_ctx = DispatchContext {
      request,
      callback: Some(once_callback),
    };

    let mut handle = tokio::task::spawn_local(async move {
      service.call(service_ctx).await.unwrap_or_else(|e| {
        tracing::error!("Dispatch runtime error: {:?}", e);
        InternalError::Other(format!("{:?}", e)).as_response()
      })
    });

    // 【2026-08-13 修复：FFI 请求永久挂起导致客户端整体卡死】
    //
    // 这里原本直接 `.await` 上面的 JoinHandle。只要 handler 内部有任何一个
    // Future 永久 pending（例如某处长期持有 folder 的 tokio RwLock 写锁，
    // 使 get_view_pb 的 `lock.read().await` 再也拿不到锁），这个 await 就
    // 永不返回：
    //   · Rust 侧：pending 的任务不占线程、没有调用栈，sample 采样里完全
    //     看不到，进程表现为「完全空闲」；
    //   · Dart 侧：dispatch.dart 用 `singleCompletePort(completer)` 等回调，
    //     Rust 不回，Completer 就永远悬着 —— 日志里表现为
    //     `TimeoutException: Future not completed`（见 2026-08-13 日志：
    //     getChildViews 连续超时，mac / Windows 均复现）。
    //   · 后果：中间栏一直转圈、断网也无法恢复、连本地私有空间都打不开。
    //
    // 与其逐个排查「究竟是哪一处持锁不放」（folder 锁在 manager.rs 里就有
    // 50 处获取点，手工核对既不可靠也挡不住以后新引入的），不如在 FFI 这一层
    // 兜住：任何 handler 都不允许无限期占用一次 FFI 调用。
    //
    // 超时后：
    //   · 立刻给 Dart 返回一个明确的错误响应，UI 能走失败分支而不是永久等待；
    //   · 打印事件名，下次复现时可直接定位是哪个 event 卡住；
    //   · abort 掉该任务，避免泄漏的任务继续持有资源。
    //
    // 60 秒是一个「正常绝不会触及、异常必然触及」的阈值：本地 FFI 调用正常在
    // 毫秒级，最慢的全量同步类操作也远低于此。Dart 侧多数调用点自身还有更短的
    // 超时（如 SpaceBloc 为 10 秒），此处只作为最后一道防线。
    const FFI_HANDLER_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(60);

    let result = match tokio::time::timeout(FFI_HANDLER_TIMEOUT, &mut handle).await {
      Ok(joined) => joined,
      Err(_) => {
        tracing::error!(
          "[dispatch]: 事件 {} 超过 {:?} 未完成，判定为挂起并中止本次调用。\
           这通常意味着 handler 内部有 Future 永久 pending（例如 folder 读写锁\
           拿不到）。已向 Dart 返回错误，避免整个 FFI 通道被拖住。",
          event_for_diagnostics,
          FFI_HANDLER_TIMEOUT,
        );
        let error = InternalError::Other(format!(
          "handler timeout after {:?}: {}",
          FFI_HANDLER_TIMEOUT, event_for_diagnostics
        ));
        let error_response = error.as_response();

        // 必须由这里主动把错误响应投递给 Dart：仅仅 return 是不够的，
        // FFI 路径的返回值会被丢弃（Runner 侧 ret 为 None）。
        let taken = shared_callback.borrow_mut().take();
        match taken {
          Some(callback) => {
            // 回调还没被 handler 取走 → handler 确实卡住了。
            // 先 abort：drop 掉挂起的 Future 会顺带释放它持有的锁 / DB 连接等
            // 资源（仅 drop，不会打断已完成的同步写入），避免一个永久 pending
            // 的任务把 folder 锁之类的公共资源一直扣着，拖垮后续所有请求。
            // 注意：只 drop JoinHandle 是「分离」而非取消，必须显式 abort。
            handle.abort();
            callback(error_response.clone()).await;
          },
          None => {
            // 回调已被 handler 取走，说明它正在投递响应（只是慢过了 60 秒）。
            // 此时不要 abort，否则会打断投递、反而让 Dart 收不到任何响应。
            tracing::warn!(
              "[dispatch]: 事件 {} 超时，但 handler 已在投递响应，交由其自行完成",
              event_for_diagnostics,
            );
          },
        }

        return error_response;
      },
    };

    result.unwrap_or_else(|e| {
      let msg = format!("EVENT_DISPATCH join error: {:?}", e);
      tracing::error!("{}", msg);
      let error = InternalError::JoinError(msg);
      error.as_response()
    })
  }

  #[cfg(not(feature = "local_set"))]
  pub async fn async_send_with_callback<Req, Callback>(
    dispatch: &AFPluginDispatcher,
    request: Req,
    callback: Callback,
  ) -> AFPluginEventResponse
  where
    Req: Into<AFPluginRequest>,
    Callback: FnOnce(AFPluginEventResponse) -> AFBoxFuture<'static, ()> + AFConcurrent + 'static,
  {
    let request: AFPluginRequest = request.into();
    let plugins = dispatch.plugins.clone();
    let service = Box::new(DispatchService { plugins });
    tracing::trace!("Async event: {:?}", &request.event);
    let service_ctx = DispatchContext {
      request,
      callback: Some(Box::new(callback)),
    };

    dispatch
      .runtime
      .spawn(async move {
        service.call(service_ctx).await.unwrap_or_else(|e| {
          tracing::error!("Dispatch runtime error: {:?}", e);
          InternalError::Other(format!("{:?}", e)).as_response()
        })
      })
      .await
      .unwrap_or_else(|e| {
        let msg = format!("EVENT_DISPATCH join error: {:?}", e);
        tracing::error!("{}", msg);
        let error = InternalError::JoinError(msg);
        error.as_response()
      })
  }

  #[cfg(not(feature = "local_set"))]
  pub async fn boxed_async_send_with_callback<Req, Callback>(
    dispatch: &AFPluginDispatcher,
    request: Req,
    callback: Callback,
  ) -> DispatchFuture<AFPluginEventResponse>
  where
    Req: Into<AFPluginRequest> + 'static,
    Callback: FnOnce(AFPluginEventResponse) -> AFBoxFuture<'static, ()> + AFConcurrent + 'static,
  {
    let request: AFPluginRequest = request.into();
    let plugins = dispatch.plugins.clone();
    let service = Box::new(DispatchService { plugins });
    tracing::trace!("[dispatch]: Async event: {:?}", &request.event);
    let service_ctx = DispatchContext {
      request,
      callback: Some(Box::new(callback)),
    };

    let handle = dispatch.runtime.spawn(async move {
      service.call(service_ctx).await.unwrap_or_else(|e| {
        tracing::error!("[dispatch]: runtime error: {:?}", e);
        InternalError::Other(format!("{:?}", e)).as_response()
      })
    });

    let runtime = dispatch.runtime.clone();
    DispatchFuture {
      fut: Box::pin(async move {
        let result = runtime.spawn(handle).await.unwrap();
        result.unwrap_or_else(|e| {
          let msg = format!("EVENT_DISPATCH join error: {:?}", e);
          tracing::error!("{}", msg);
          let error = InternalError::JoinError(msg);
          error.as_response()
        })
      }),
    }
  }

  #[cfg(feature = "local_set")]
  pub fn sync_send(
    dispatch: Arc<AFPluginDispatcher>,
    request: AFPluginRequest,
  ) -> AFPluginEventResponse {
    futures::executor::block_on(AFPluginDispatcher::async_send_with_callback(
      dispatch.as_ref(),
      request,
      |_| Box::pin(async {}),
    ))
  }
}

#[derive(Derivative)]
#[derivative(Debug)]
pub struct DispatchContext {
  pub request: AFPluginRequest,
  #[derivative(Debug = "ignore")]
  pub callback: Option<BoxFutureCallback>,
}

impl DispatchContext {
  pub(crate) fn into_parts(self) -> (AFPluginRequest, Option<BoxFutureCallback>) {
    let DispatchContext { request, callback } = self;
    (request, callback)
  }
}

pub(crate) struct DispatchService {
  pub(crate) plugins: AFPluginMap,
}

impl Service<DispatchContext> for DispatchService {
  type Response = AFPluginEventResponse;
  type Error = DispatchError;
  type Future = AFBoxFuture<'static, Result<Self::Response, Self::Error>>;

  #[tracing::instrument(name = "DispatchService", level = "debug", skip(self, ctx))]
  fn call(&self, ctx: DispatchContext) -> Self::Future {
    let module_map = self.plugins.clone();
    let (request, callback) = ctx.into_parts();

    Box::pin(async move {
      let result = {
        match module_map.get(&request.event) {
          Some(module) => {
            let event = format!("{:?}", request.event);
            event!(
              tracing::Level::TRACE,
              "[dispatch]: {:?} exec event:{}",
              &module.name,
              &event,
            );
            let fut = module.new_service(());
            let service_fut = fut.await?.call(request);
            let result = service_fut.await;
            event!(
              tracing::Level::TRACE,
              "[dispatch]: {:?} exec event:{} with result: {}",
              &module.name,
              &event,
              result.is_ok()
            );
            result
          },
          None => {
            let msg = format!("[dispatch]: can not find the event handler. {:?}", request);
            event!(tracing::Level::ERROR, "{}", msg);
            Err(InternalError::HandleNotFound(msg).into())
          },
        }
      };

      let response = result.unwrap_or_else(|e| e.into());
      event!(tracing::Level::TRACE, "Dispatch result: {:?}", response);
      if let Some(callback) = callback {
        callback(response.clone()).await;
      }

      Ok(response)
    })
  }
}

#[allow(dead_code)]
fn plugin_info(plugins: &[AFPlugin]) -> String {
  let mut info = format!("{} plugins loaded\n", plugins.len());
  for module in plugins {
    info.push_str(&format!("-> {} loaded \n", module.name));
  }
  info
}

#[allow(dead_code)]
fn print_plugins(plugins: &AFPluginMap) {
  plugins.iter().for_each(|(k, v)| {
    tracing::info!("Event: {:?} plugin : {:?}", k, v.name);
  })
}

#[pin_project]
pub struct DispatchFuture<T: AFConcurrent> {
  #[pin]
  pub fut: Pin<Box<dyn Future<Output = T> + 'static>>,
}

impl<T> Future for DispatchFuture<T>
where
  T: AFConcurrent + 'static,
{
  type Output = T;

  fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
    let this = self.as_mut().project();
    Poll::Ready(futures_core::ready!(this.fut.poll(cx)))
  }
}
