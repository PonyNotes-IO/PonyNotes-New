// ========================================================================
// flutter 桥接功能
// 这个文件将以阻塞行为模式，第一个执行。这时画板的任何代码还未初始化
// ========================================================================
// 功能列表：
//  - localStorage hook，根据viewId隔离，仅作为短期镜像
// ========================================================================
// 目的：让每个白板视图(viewId)使用独立的localStorage命名空间
// 原理：拦截localStorage API，自动添加viewId前缀，避免跨白板污染
// ========================================================================
(async function () {
    console.log('[PonyNotes] 🔐 Initializing localStorage isolation...');

    // 【插图修复 2026-09-01】白板插图改由 Flutter 原生选图 + WebView 侧降采样。
    // 根因：Excalidraw 插图会把图缩到 ≤1440px 后**重编码**，照片按无损 PNG
    // 重编码后体积常 >4MB，命中内部 fileTooBig 抛错；该错误被 insertImages 的
    // catch→console.error 吞掉（不在 Dart 日志白名单），元素被 newElement:null
    // 静默丢弃 —— 表现为「插图不显示」。
    // 方案：拦截 image 类型 <input> 的 click，转调 Flutter 原生选图取字节，在
    // canvas 内降采样到 ≤1440px、照片转 JPEG，保证 <3.5MB（给 4MB 上限留余量），
    // 再经 DataTransfer 回填 input.files + dispatch change，交由 Excalidraw 原生
    // 插图管线建元素（<4MB 时该管线已被实测可靠）。任何异常回退原始 click（原生
    // 面板），保证不劣化。仅在桌面 file input 生效，不触碰移动端/协作空间路径。
    installWhiteboardImagePicker();
    function installWhiteboardImagePicker() {
        try {
            if (typeof HTMLInputElement === 'undefined' ||
                !HTMLInputElement.prototype ||
                HTMLInputElement.prototype.__ponynotesImagePickerPatched) {
                return;
            }
            // 仅当宿主提供了原生选图 handler 时才接管；否则保持原生 <input> 行为。
            if (!window.flutter_inappwebview ||
                typeof window.flutter_inappwebview.callHandler !== 'function') {
                return;
            }
            const originalClick = HTMLInputElement.prototype.click;
            HTMLInputElement.prototype.click = function () {
                try {
                    const isFile = (this.type || '').toLowerCase() === 'file';
                    const accept = (this.accept || '').toLowerCase();
                    // Excalidraw 插图 input 的 accept 一定含 image/*（png/jpeg/...）。
                    // 库导入(.excalidrawlib)、场景加载(.excalidraw)等不含 image/，放行。
                    const isImage = isFile && accept.indexOf('image/') !== -1;
                    if (!isImage) {
                        return originalClick.apply(this, arguments);
                    }
                    _ponynotesPickImageInto(this, originalClick);
                } catch (e) {
                    console.warn('[PonyNotes] whiteboard image insert intercept error: ' +
                        (e && e.message || e));
                    return originalClick.apply(this, arguments);
                }
            };
            HTMLInputElement.prototype.__ponynotesImagePickerPatched = true;
            console.log('[PonyNotes] whiteboard image picker installed');
        } catch (err) {
            console.warn('[PonyNotes] whiteboard image picker install error: ' +
                (err && err.message || err));
        }
    }
    // 取消/失败时用 Excalidraw 自己的清理路径收尾：legacySetup 在 window focus
    // 时会检查 input.files，为空则触发 AbortError 并 clearInterval、移除监听、
    // 把工具切回选择态。派发一个 focus 事件即可复用这套收尾，避免选择器 Promise
    // 悬挂导致工具卡在「图片」态。
    function _ponynotesCancelImagePick() {
        try {
            window.dispatchEvent(new Event('focus'));
        } catch (e) { /* 收尾失败不致命：仅工具态未复位 */ }
    }

    async function _ponynotesPickImageInto(input, originalClick) {
        let picked;
        try {
            picked = await window.flutter_inappwebview.callHandler('pickWhiteboardImage');
        } catch (e) {
            console.warn('[PonyNotes] whiteboard image insert: native picker handler failed: ' +
                (e && e.message || e));
            return originalClick.apply(input, []);
        }
        if (!picked || typeof picked !== 'object') {
            // 宿主未实现或返回异常：回退原生面板，保证仍可插图。
            return originalClick.apply(input, []);
        }
        if (picked.canceled) {
            _ponynotesCancelImagePick();
            return;
        }
        if (picked.error || !picked.base64) {
            console.warn('[PonyNotes] whiteboard image insert: picker returned error: ' +
                (picked.error || 'no base64'));
            _ponynotesCancelImagePick();
            return;
        }
        try {
            const srcBlob = _ponynotesBase64ToBlob(picked.base64, picked.mimeType || 'image/png');
            const processed = await _ponynotesDownscaleImage(
                srcBlob, picked.mimeType || 'image/png', picked.name || 'image.png');
            // 【插图确定性重写 2026-09-01】不再派发 change 走 Excalidraw 的
            // fileOpen→change→Promise 链。该链靠窗口 focus 取消探测 + 5s 轮询判断
            // 是否取消，会与私有白板「本地写入→云端回灌→重绘」竞态：实测第二次
            // 插图的 insertImages 因此从未执行，元素没建也没存，退出重进只剩第一张。
            // 改为桥接层直接 addFiles + 造 image 元素 + updateScene 写入场景，
            // 确定性最高，免疫焦点/云回灌竞态。仅在 API 未就绪时才回退 change 注入。
            const inserted = await _ponynotesInsertImageViaAPI(processed);
            if (inserted) {
                // 直插成功：Excalidraw 的 fileOpen Promise 仍悬挂（我们拦了 click 未派发
                // change）。派发 focus 触发其 AbortError 收尾，把工具态从「图片」复位，
                // 避免工具卡住。收尾不影响已写入的元素。
                _ponynotesCancelImagePick();
                console.log('[PonyNotes] whiteboard image insert: inserted via API ' +
                    processed.name + ' (' + processed.type + ', ' +
                    processed.blob.size + ' bytes)');
                return;
            }
            // API 未就绪：回退到 change 注入，仍走 Excalidraw 原生插图管线。
            const file = new File([processed.blob], processed.name,
                { type: processed.type, lastModified: Date.now() });
            _ponynotesAssignInputFile(input, file);
            console.log('[PonyNotes] whiteboard image insert: injected via change ' +
                processed.name + ' (' + processed.type + ', ' +
                processed.blob.size + ' bytes)');
        } catch (e) {
            console.warn('[PonyNotes] whiteboard image insert: insert failed, ' +
                'falling back to native picker: ' + (e && e.message || e));
            return originalClick.apply(input, []);
        }
    }
    function _ponynotesBase64ToBlob(base64, mimeType) {
        const binary = atob(base64);
        const len = binary.length;
        const bytes = new Uint8Array(len);
        for (let i = 0; i < len; i++) {
            bytes[i] = binary.charCodeAt(i);
        }
        return new Blob([bytes], { type: mimeType || 'application/octet-stream' });
    }

    function _ponynotesAssignInputFile(input, file) {
        // 现代 WebKit（含 macOS WKWebView）支持用 DataTransfer 写 input.files。
        if (typeof DataTransfer === 'function') {
            const dt = new DataTransfer();
            dt.items.add(file);
            input.files = dt.files;
        } else {
            // 兜底：直接定义只读的 files（旧内核）。
            Object.defineProperty(input, 'files', {
                configurable: true,
                value: [file],
            });
        }
        // Excalidraw 既监听 change，也用 legacySetup 轮询 input.files；派发 change
        // 走首选路径，轮询作为兜底，二者都读同一份注入的 file。
        input.dispatchEvent(new Event('change', { bubbles: true }));
    }

    // ---- 直接 API 插图（绕开 fileOpen/change 链）----------------------------
    // processed: { blob, type, name }。返回 true=已写入场景；false=API 未就绪需回退。
    async function _ponynotesInsertImageViaAPI(processed) {
        const api = window._excalidrawAPI;
        if (!api || typeof api.addFiles !== 'function' ||
            typeof api.updateScene !== 'function' ||
            typeof api.getSceneElementsIncludingDeleted !== 'function') {
            return false;
        }
        const dataURL = await _ponynotesBlobToDataURL(processed.blob);
        if (typeof dataURL !== 'string' || !dataURL.startsWith('data:image/')) {
            return false;
        }
        // fileId 用 SHA-1(dataURL) 的十六进制，和 Excalidraw 的内容哈希口径一致，
        // 便于文件缓存/云端按内容去重。计算失败时退回随机 id（不影响本地显示）。
        const fileId = await _ponynotesComputeFileId(dataURL);
        const mimeType = processed.type || 'image/png';
        api.addFiles([{
            id: fileId,
            dataURL,
            mimeType,
            created: Date.now(),
        }]);

        const dims = await _ponynotesDecodeImageDims(dataURL);
        const appState = typeof api.getAppState === 'function' ? api.getAppState() : {};
        const placement = _ponynotesComputeImagePlacement(appState, dims);

        const now = Date.now();
        const element = {
            id: _ponynotesRandomId(),
            type: 'image',
            x: placement.x,
            y: placement.y,
            width: placement.width,
            height: placement.height,
            angle: 0,
            strokeColor: 'transparent',
            backgroundColor: 'transparent',
            fillStyle: 'solid',
            strokeWidth: 1,
            strokeStyle: 'solid',
            roughness: 1,
            opacity: 100,
            groupIds: [],
            frameId: null,
            index: null,
            roundness: null,
            seed: _ponynotesRandomSeed(),
            version: 1,
            versionNonce: _ponynotesRandomSeed(),
            isDeleted: false,
            boundElements: null,
            updated: now,
            link: null,
            locked: false,
            customData: undefined,
            status: 'saved',
            fileId,
            scale: [1, 1],
            crop: null,
        };

        const current = api.getSceneElementsIncludingDeleted() || [];
        api.updateScene({
            elements: current.concat([element]),
            appState: { selectedElementIds: { [element.id]: true } },
            commitToHistory: true,
        });

        // 首次插图时 WebView 视口偶发 0x0，导致元素落在可视区外。滚动到该元素，
        // 确保用户立即看见。decode/refresh 由 installIOSImageDecodeRefresh 兜底。
        if (typeof api.scrollToContent === 'function') {
            try {
                api.scrollToContent(element, { fitToContent: false, animate: false });
            } catch (_) { /* 滚动失败不致命 */ }
        }
        if (typeof api.refresh === 'function') {
            api.refresh();
            requestAnimationFrame(() => api.refresh());
        }
        return true;
    }

    function _ponynotesBlobToDataURL(blob) {
        return new Promise((resolve) => {
            try {
                const reader = new FileReader();
                reader.onload = () => resolve(reader.result);
                reader.onerror = () => resolve(null);
                reader.readAsDataURL(blob);
            } catch (e) {
                resolve(null);
            }
        });
    }

    async function _ponynotesComputeFileId(dataURL) {
        try {
            if (window.crypto && window.crypto.subtle &&
                typeof TextEncoder === 'function') {
                const bytes = new TextEncoder().encode(dataURL);
                const digest = await window.crypto.subtle.digest('SHA-1', bytes);
                const arr = Array.from(new Uint8Array(digest));
                return arr.map(b => b.toString(16).padStart(2, '0')).join('');
            }
        } catch (e) { /* 退回随机 id */ }
        return _ponynotesRandomId();
    }

    function _ponynotesDecodeImageDims(dataURL) {
        return new Promise((resolve) => {
            try {
                const img = new Image();
                const timer = setTimeout(
                    () => resolve({ width: 0, height: 0 }), 5000);
                img.onload = () => {
                    clearTimeout(timer);
                    resolve({
                        width: img.naturalWidth || 0,
                        height: img.naturalHeight || 0,
                    });
                };
                img.onerror = () => {
                    clearTimeout(timer);
                    resolve({ width: 0, height: 0 });
                };
                img.src = dataURL;
            } catch (e) {
                resolve({ width: 0, height: 0 });
            }
        });
    }

    // 与 installIOSImageDecodeRefresh 的零尺寸修复口径一致：高度 ≤ 视口一半，
    // 保持原始宽高比，放在当前视口中心（场景坐标）。
    function _ponynotesComputeImagePlacement(appState, dims) {
        const zoom = Number(appState?.zoom?.value) || 1;
        const scrollX = Number(appState?.scrollX) || 0;
        const scrollY = Number(appState?.scrollY) || 0;
        const viewportWidth = Number(appState?.width) > 0
            ? Number(appState.width)
            : Number(window.innerWidth) || 375;
        const viewportHeight = Number(appState?.height) > 0
            ? Number(appState.height)
            : Number(window.innerHeight) || 707;

        const natW = Number(dims?.width) || 0;
        const natH = Number(dims?.height) || 0;

        let width;
        let height;
        if (natW > 0 && natH > 0) {
            const maxHeight = Math.min(
                Math.max(viewportHeight - 120, 160),
                Math.floor(viewportHeight * 0.5) / zoom,
            );
            height = Math.min(natH, maxHeight);
            width = height * (natW / natH);
            const maxWidth = Math.floor(viewportWidth * 0.9) / zoom;
            if (width > maxWidth) {
                width = maxWidth;
                height = width * (natH / natW);
            }
        } else {
            // 尺寸未知：给一个合理默认，交由 onChange 的零尺寸修复兜底纠正。
            width = Math.floor(viewportWidth * 0.5) / zoom;
            height = width;
        }

        // 视口中心的屏幕坐标 → 场景坐标：sceneX = screenX/zoom - scrollX
        const centerSceneX = (viewportWidth / 2) / zoom - scrollX;
        const centerSceneY = (viewportHeight / 2) / zoom - scrollY;
        return {
            x: centerSceneX - width / 2,
            y: centerSceneY - height / 2,
            width,
            height,
        };
    }

    function _ponynotesRandomId() {
        try {
            if (window.crypto && typeof window.crypto.getRandomValues === 'function') {
                const bytes = new Uint8Array(20);
                window.crypto.getRandomValues(bytes);
                return Array.from(bytes)
                    .map(b => b.toString(16).padStart(2, '0')).join('');
            }
        } catch (e) { /* 退回 Math.random */ }
        return 'id' + Math.random().toString(36).slice(2) + Date.now().toString(36);
    }

    function _ponynotesRandomSeed() {
        try {
            if (window.crypto && typeof window.crypto.getRandomValues === 'function') {
                const arr = new Uint32Array(1);
                window.crypto.getRandomValues(arr);
                return arr[0];
            }
        } catch (e) { /* 退回 Math.random */ }
        return Math.floor(Math.random() * 2147483647);
    }
    // Excalidraw 内部上限：缩放到 ≤1440px、重编码后 >4MB 即 fileTooBig。
    // 我们预降采样到 ≤1440px 并把体积压到 <3.5MB（留 0.5MB 余量），使其原生
    // 插图管线稳过 fileTooBig。SVG/GIF 不光栅化（避免丢矢量/动画），仅在其本身
    // 已 <3.5MB 时透传，否则也交原生（极少见）。
    const _PONY_MAX_DIM = 1440;
    const _PONY_MAX_BYTES = Math.floor(3.5 * 1024 * 1024);

    async function _ponynotesDownscaleImage(blob, mimeType, name) {
        const type = (mimeType || '').toLowerCase();
        // 矢量图/动图不光栅化：本身够小直接透传，交由原生管线。
        if (type === 'image/svg+xml' || type === 'image/gif') {
            return { blob, type: mimeType, name };
        }
        if (typeof createImageBitmap !== 'function' ||
            typeof document.createElement !== 'function') {
            // 无法在 WebView 内解码/编码：透传原始字节。
            return { blob, type: mimeType, name };
        }

        let bitmap;
        try {
            bitmap = await createImageBitmap(blob);
        } catch (e) {
            // 解码失败（罕见格式）：透传原始字节，交原生管线兜底。
            return { blob, type: mimeType, name };
        }

        const srcW = bitmap.width || 1;
        const srcH = bitmap.height || 1;
        const scale = Math.min(1, _PONY_MAX_DIM / Math.max(srcW, srcH));
        const dstW = Math.max(1, Math.round(srcW * scale));
        const dstH = Math.max(1, Math.round(srcH * scale));

        const canvas = document.createElement('canvas');
        canvas.width = dstW;
        canvas.height = dstH;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(bitmap, 0, 0, dstW, dstH);
        if (typeof bitmap.close === 'function') bitmap.close();

        const hasAlpha = type === 'image/png' || type === 'image/webp';
        // 先按原格式（PNG 保留透明）编码；若超阈值则转 JPEG 逐级降质，直到 <3.5MB。
        let outType = hasAlpha ? 'image/png' : 'image/jpeg';
        let out = await _ponynotesCanvasToBlob(canvas, outType, 0.92);
        if (out && out.size > _PONY_MAX_BYTES) {
            for (const q of [0.85, 0.72, 0.6, 0.45]) {
                const jpeg = await _ponynotesCanvasToBlob(canvas, 'image/jpeg', q);
                if (jpeg) {
                    out = jpeg;
                    outType = 'image/jpeg';
                    if (jpeg.size <= _PONY_MAX_BYTES) break;
                }
            }
        }
        if (!out) {
            // 编码失败：退回原始 blob（可能仍 >4MB，但由原生管线决定，不静默）。
            return { blob, type: mimeType, name };
        }
        const outName = _ponynotesRenameForType(name, outType);
        return { blob: out, type: outType, name: outName };
    }

    function _ponynotesCanvasToBlob(canvas, type, quality) {
        return new Promise((resolve) => {
            try {
                canvas.toBlob((b) => resolve(b), type, quality);
            } catch (e) {
                resolve(null);
            }
        });
    }

    // 编码格式变了就同步换扩展名，避免 name 与真实字节类型不一致。
    function _ponynotesRenameForType(name, type) {
        const base = (name || 'image').replace(/\.[^.]+$/, '');
        const ext = type === 'image/jpeg' ? 'jpg'
            : type === 'image/png' ? 'png'
                : type === 'image/webp' ? 'webp' : 'png';
        return base + '.' + ext;
    }

    // 保存原始localStorage的引用
    const originalLocalStorage = window.localStorage;
    const urlParams = new URLSearchParams(window.location.search || '');
    const whiteboardViewId = urlParams.get('viewId') || 'default';
    const useMemoryStorage = urlParams.get('storageMode') === 'memory';
    const storagePrefix = `ponynotes:whiteboard:${encodeURIComponent(whiteboardViewId)}:`;
    const rawWhiteboardKeys = new Set([
        'excalidraw',
        'excalidraw-state',
        'excalidraw-files',
        'excalidraw-theme'
    ]);

    const scopedStorageKey = (key) => `${storagePrefix}${key}`;
    // macOS WKWebView 的 localStorage 配额固定且按来源共享。
    // macOS 模式下，白板场景只放在当前 WebView 内存中；Flutter/collab
    // 仍通过 localStorageOnSet 接收并持久化变更，因此切换/重启不依赖该镜像。
    const memoryStorage = new Map();

    const scopedStorageKeys = () => {
        const keys = [];
        for (let i = 0; i < originalLocalStorage.length; i++) {
            const key = originalLocalStorage.key(i);
            if (key && key.startsWith(storagePrefix)) {
                keys.push(key);
            }
        }
        return keys;
    };

    const clearCurrentWhiteboardStorage = () => {
        for (const key of scopedStorageKeys()) {
            originalLocalStorage.removeItem(key);
        }
        for (const key of rawWhiteboardKeys) {
            originalLocalStorage.removeItem(key);
        }
    };

    let init = false;

    // ✅ 关键修复：保存 initData 返回的权威数据，避免竞态条件
    // 原因：Excalidraw 的脚本可能在 initData 完成之前就读取 localStorage
    // 如果此时 localStorage 是空的（被 clear() 清掉），Excalidraw 会写入空数据 '[]'
    // 覆盖 initData 后续设置的正确数据。
    // 解决方案：将 initData 返回的数据保存到 JS 变量中，
    // 在 _injectFilesFromStorage 中使用此变量而非 localStorage
    let _initPayload = null;
    // 宿主主题是白板唯一主题来源；白板内置主题选择会被自动纠正。
    let _applyingHostTheme = false;
    const initialHostTheme = urlParams.get('hostTheme');
    let _forcedHostTheme = initialHostTheme === 'dark' || initialHostTheme === 'light'
        ? initialHostTheme
        : null;
    let _pendingHostTheme = null;
    let _iosImageRefreshAPI = null;
    let _iosImageSceneSyncTimer = null;
    let _iosImageSceneSyncPending = null;
    let _iosImageSceneSyncLastSignature = null;
    let _iosImageSceneSyncAttempts = 0;
    let _iosImageSceneSyncInFlight = false;
    let _iosImageSceneSyncInFlightPromise = null;

    const isIOSWebView = () => {
        const userAgent = navigator.userAgent || '';
        return /iPad|iPhone|iPod/.test(userAgent) ||
            (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    };

    const getImageViewportSnapshot = (element, appState) => {
        const zoom = Number(appState?.zoom?.value) || 1;
        const offsetLeft = Number(appState?.offsetLeft) || 0;
        const offsetTop = Number(appState?.offsetTop) || 0;
        const scrollX = Number(appState?.scrollX) || 0;
        const scrollY = Number(appState?.scrollY) || 0;
        const width = Number(appState?.width) || 0;
        const height = Number(appState?.height) || 0;
        const left = (Number(element.x) + scrollX) * zoom + offsetLeft;
        const top = (Number(element.y) + scrollY) * zoom + offsetTop;
        const right = left + Number(element.width) * zoom;
        const bottom = top + Number(element.height) * zoom;
        const viewportRight = offsetLeft + width;
        const viewportBottom = offsetTop + height;

        return {
            elementId: element.id,
            fileId: element.fileId,
            status: element.status,
            x: element.x,
            y: element.y,
            width: element.width,
            height: element.height,
            scrollX,
            scrollY,
            zoom,
            viewportWidth: width,
            viewportHeight: height,
            centerViewportX: (left + right) / 2,
            centerViewportY: (top + bottom) / 2,
            isVisible: right > offsetLeft && left < viewportRight &&
                bottom > offsetTop && top < viewportBottom,
        };
    };

    const parseSceneCollection = (value) => {
        if (typeof value !== 'string') return value;
        try {
            return JSON.parse(value);
        } catch (_) {
            return value;
        }
    };

    const isBlankScenePayload = (data) => {
        const elements = parseSceneCollection(
            data?.elements ?? data?.excalidraw,
        );
        const files = parseSceneCollection(
            data?.files ?? data?.['excalidraw-files'],
        );
        const hasElements = Array.isArray(elements)
            ? elements.length > 0
            : !!elements;
        const hasFiles = files && typeof files === 'object'
            ? Object.keys(files).length > 0
            : !!files;
        return !hasElements && !hasFiles;
    };

    // Recover images inserted while an embedded WebView is still settling its
    // layout. iOS also gets the decode/viewport diagnostics, while desktop
    // only enters this path for a zero-sized image element.
    const installIOSImageDecodeRefresh = (api) => {
        if (!api || _iosImageRefreshAPI === api ||
            typeof api.onChange !== 'function' || typeof api.refresh !== 'function') {
            return;
        }

        _iosImageRefreshAPI = api;
        const decodedFileIds = new Set();

        api.onChange((elements, appState, files) => {
            queueIOSImageSceneSync(elements, files);
            for (const element of elements || []) {
                if (!element || element.isDeleted || element.type !== 'image' ||
                    !element.fileId || decodedFileIds.has(element.fileId)) {
                    continue;
                }

                const file = files && files[element.fileId];
                if (!file || typeof file.dataURL !== 'string' ||
                    !file.dataURL.startsWith('data:image/')) {
                    continue;
                }

                decodedFileIds.add(element.fileId);
                const image = new Image();
                const loaded = new Promise((resolve, reject) => {
                    const timeout = setTimeout(
                        () => reject(new Error('image load timeout')),
                        5000,
                    );
                    image.onload = () => {
                        clearTimeout(timeout);
                        resolve();
                    };
                    image.onerror = () => {
                        clearTimeout(timeout);
                        reject(new Error('image load failed'));
                    };
                });
                image.src = file.dataURL;

                (async () => {
                    try {
                        await loaded;
                        if (typeof image.decode === 'function') {
                            await image.decode();
                        }
                        const decodedMessage =
                            (isIOSWebView() ? '[PonyNotes] iOS image decoded, refreshing canvas: '
                                : '[PonyNotes] image decoded, refreshing canvas: ') +
                            element.fileId + ' (' + image.naturalWidth + 'x' +
                            image.naturalHeight + ')';
                        console.log(decodedMessage);
                    } catch (error) {
                        // Some WebKit versions reject decode() even after onload. A
                        // delayed refresh still gives the internal image cache a new
                        // paint opportunity and does not alter the scene.
                        const fallbackMessage =
                            (isIOSWebView() ? '[PonyNotes] iOS image decode fallback: '
                                : '[PonyNotes] image decode fallback: ') +
                            element.fileId + ' - ' + (error?.message || error);
                        console.warn(fallbackMessage);
                    }

                    let latestElement = typeof api.getSceneElementsIncludingDeleted === 'function'
                        ? api.getSceneElementsIncludingDeleted().find(
                            candidate => candidate.id === element.id,
                        )
                        : element;
                    let latestAppState = typeof api.getAppState === 'function'
                        ? api.getAppState()
                        : appState;

                    // Dismissing UIDocumentPicker can leave Excalidraw with a
                    // stale 0x0 viewport until the next resize event. Ask the
                    // editor to remeasure before inspecting or repairing the image.
                    if (Number(latestAppState?.width) <= 0 ||
                        Number(latestAppState?.height) <= 0) {
                        window.dispatchEvent(new Event('resize'));
                        await new Promise(resolve => requestAnimationFrame(resolve));
                        latestAppState = typeof api.getAppState === 'function'
                            ? api.getAppState()
                            : latestAppState;
                    }

                    if (latestElement &&
                        (Number(latestElement.width) <= 0 ||
                            Number(latestElement.height) <= 0) &&
                        image.naturalWidth > 0 && image.naturalHeight > 0) {
                        const zoom = Number(latestAppState?.zoom?.value) || 1;
                        const viewportHeight = Number(latestAppState?.height) > 0
                            ? Number(latestAppState.height)
                            : Number(window.innerHeight) || 707;
                        const maxHeight = Math.min(
                            Math.max(viewportHeight - 120, 160),
                            Math.floor(viewportHeight * 0.5) / zoom,
                        );
                        const repairedHeight = Math.min(
                            image.naturalHeight,
                            maxHeight,
                        );
                        const repairedWidth = repairedHeight *
                            (image.naturalWidth / image.naturalHeight);
                        const repairs = {
                            x: Number(latestElement.x) +
                                Number(latestElement.width) / 2 - repairedWidth / 2,
                            y: Number(latestElement.y) +
                                Number(latestElement.height) / 2 - repairedHeight / 2,
                            width: repairedWidth,
                            height: repairedHeight,
                            crop: null,
                        };

                        if (typeof api.mutateElement === 'function') {
                            api.mutateElement(latestElement, repairs);
                        } else if (typeof api.updateScene === 'function' &&
                            typeof api.getSceneElementsIncludingDeleted === 'function') {
                            api.updateScene({
                                elements: api.getSceneElementsIncludingDeleted().map(
                                    candidate => candidate.id === latestElement.id
                                        ? { ...candidate, ...repairs }
                                        : candidate,
                                ),
                            });
                        }

                        latestElement = typeof api.getSceneElementsIncludingDeleted === 'function'
                            ? api.getSceneElementsIncludingDeleted().find(
                                candidate => candidate.id === element.id,
                            ) || { ...latestElement, ...repairs }
                            : { ...latestElement, ...repairs };
                        const repairMessage =
                            (isIOSWebView() ? '[PonyNotes] iOS zero-size image repaired: '
                                : '[PonyNotes] zero-size image repaired: ') +
                            element.fileId + ' (' + repairedWidth + 'x' +
                            repairedHeight + ')';
                        console.log(repairMessage);
                    }

                    const snapshot = getImageViewportSnapshot(
                        latestElement || element,
                        latestAppState || appState,
                    );
                    const viewportMessage = isIOSWebView()
                        ? '[PonyNotes] iOS image viewport: '
                        : '[PonyNotes] image viewport: ';
                    console.log(viewportMessage + JSON.stringify(snapshot));

                    if (!snapshot.isVisible && latestElement &&
                        snapshot.width > 0 && snapshot.height > 0 &&
                        snapshot.viewportWidth > 0 && snapshot.viewportHeight > 0 &&
                        typeof api.scrollToContent === 'function') {
                        api.scrollToContent(latestElement, {
                            fitToContent: false,
                            animate: false,
                        });
                        console.log(
                            '[PonyNotes] iOS image viewport corrected: ' +
                            element.fileId,
                        );
                    }

                    api.refresh();
                    requestAnimationFrame(() => api.refresh());
                })();
            }
        });

        console.log('[PonyNotes] iOS image decode refresh installed');
    };

    // UIDocumentPicker can temporarily hide WKWebView. During that window
    // Excalidraw pauses LocalData, so localStorage.setItem is not a reliable
    // source of the first image scene. Send the matching elements and files as
    // one acknowledged bridge message directly from Excalidraw's onChange.
    const queueIOSImageSceneSync = (elements, files) => {
        if (!isIOSWebView() || !init || !Array.isArray(elements) ||
            !files || typeof files !== 'object') {
            return;
        }

        const imageFileIds = elements
            .filter((element) => element && !element.isDeleted &&
                element.type === 'image' && typeof element.fileId === 'string' &&
                files[element.fileId] && typeof files[element.fileId].dataURL === 'string')
            .map((element) => element.fileId);
        if (!imageFileIds.length) {
            return;
        }

        const imageFiles = {};
        for (const fileId of imageFileIds) {
            imageFiles[fileId] = files[fileId];
        }
        const signature = JSON.stringify({
            elements: elements
                .filter((element) => element && !element.isDeleted &&
                    element.type === 'image' && imageFiles[element.fileId])
                .map((element) => [
                    element.id,
                    element.fileId,
                    element.version || 0,
                    element.versionNonce || 0,
                    element.status || '',
                ]),
            files: imageFileIds.map((fileId) => [
                fileId,
                imageFiles[fileId].dataURL.length,
                imageFiles[fileId].created || 0,
            ]),
        });
        if (signature === _iosImageSceneSyncLastSignature) {
            return;
        }

        _iosImageSceneSyncPending = { elements, files: imageFiles, signature };
        _iosImageSceneSyncAttempts = 0;
        scheduleIOSImageSceneSyncFlush();
    };

    const scheduleIOSImageSceneSyncFlush = (delay = 0) => {
        if (_iosImageSceneSyncTimer || _iosImageSceneSyncInFlight) {
            return;
        }
        _iosImageSceneSyncTimer = setTimeout(flushIOSImageSceneSync, delay);
    };

    const flushIOSImageSceneSync = () => {
        _iosImageSceneSyncTimer = null;
        if (_iosImageSceneSyncInFlight) {
            return _iosImageSceneSyncInFlightPromise || Promise.resolve();
        }
        const payload = _iosImageSceneSyncPending;
        if (!payload || payload.signature === _iosImageSceneSyncLastSignature) {
            return Promise.resolve();
        }

        _iosImageSceneSyncInFlight = true;
        let retryDelay = 0;
        const request = (async () => {
            try {
                await window.flutter_inappwebview.callHandler(
                    'whiteboardImageSceneSnapshot',
                    { elements: payload.elements, files: payload.files },
                );
                _iosImageSceneSyncLastSignature = payload.signature;
                _iosImageSceneSyncAttempts = 0;
                if (_iosImageSceneSyncPending === payload) {
                    _iosImageSceneSyncPending = null;
                }
                console.log(
                    '[PonyNotes] iOS image scene delivered: elements=' +
                    payload.elements.length + ', files=' + Object.keys(payload.files).length,
                );
            } catch (error) {
                _iosImageSceneSyncAttempts += 1;
                console.warn(
                    '[PonyNotes] iOS image scene delivery failed, retry=' +
                    _iosImageSceneSyncAttempts + ': ' + (error?.message || error),
                );
                if (_iosImageSceneSyncAttempts <= 3 && _iosImageSceneSyncPending === payload) {
                    retryDelay = 250 * _iosImageSceneSyncAttempts;
                }
            } finally {
                _iosImageSceneSyncInFlight = false;
                // A later onChange can replace the pending snapshot while the
                // native handler is awaiting. Always drain that newest snapshot
                // after this request completes; otherwise the next user action
                // would be required to make it leave the queue.
                if (_iosImageSceneSyncPending &&
                    _iosImageSceneSyncPending.signature !== _iosImageSceneSyncLastSignature &&
                    _iosImageSceneSyncAttempts <= 3) {
                    scheduleIOSImageSceneSyncFlush(retryDelay);
                }
            }
        })();
        _iosImageSceneSyncInFlightPromise = request;
        request.then(() => {
            if (_iosImageSceneSyncInFlightPromise === request) {
                _iosImageSceneSyncInFlightPromise = null;
            }
        });
        return request;
    };

    // Excalidraw 的工具栏主题由 useHandleAppTheme 的 React 状态维护，
    // 仅调用 excalidrawAPI.updateScene() 只能改变画布 appState，不能保证
    // React 外壳同步更新。集成版 Excalidraw 通过该 setter 暴露宿主主题入口。
    const syncExcalidrawReactTheme = (theme) => {
        if (typeof window.__ponynotesApplyReactTheme === 'function') {
            window.__ponynotesApplyReactTheme(theme);
            return;
        }

        const setter = window.__ponynotesSetHostTheme;
        if (typeof setter !== 'function') return;

        const last = window.__ponynotesReactThemeState;
        if (last && last.setter === setter && last.theme === theme) return;

        try {
            setter(theme);
            window.__ponynotesReactThemeState = { setter, theme };
        } catch (e) {
            console.warn('[PonyNotes] Failed to synchronize React editor theme:', e);
        }
    };

    const getPayloadTheme = (payload) => {
        if (!payload || typeof payload !== 'object') return null;
        let appState = payload.appState || payload['excalidraw-state'];
        if (typeof appState === 'string') {
            try { appState = JSON.parse(appState); } catch (e) { return null; }
        }
        const theme = appState && appState.theme;
        return theme === 'dark' || theme === 'light' ? theme : null;
    };

    // React 重绘时 .theme--dark 可能短暂被移除。额外维护一条由宿主控制的
    // CSS 规则，以 html.dark 直接驱动画布滤镜，避免画布在切换窗口露白。
    const ensureHostThemeStyle = () => {
        let style = document.getElementById('ponynotes-host-theme-style');
        if (!style) {
            style = document.createElement('style');
            style.id = 'ponynotes-host-theme-style';
            (document.head || document.documentElement).appendChild(style);
        }
        style.textContent = `
            html.dark #root .excalidraw canvas.excalidraw__canvas,
            html.dark #root .excalidraw canvas.static,
            html.dark #root .excalidraw canvas.interactive {
                -webkit-filter: invert(93%) hue-rotate(180deg) !important;
                filter: invert(93%) hue-rotate(180deg) !important;
            }
            html.dark #root .excalidraw {
                background-color: #121212 !important;
            }
            html:not(.dark) #root .excalidraw canvas.excalidraw__canvas,
            html:not(.dark) #root .excalidraw canvas.static,
            html:not(.dark) #root .excalidraw canvas.interactive {
                -webkit-filter: none !important;
                filter: none !important;
            }
        `;
    };

    const applyHostThemeToScene = (theme) => {
        const normalizedTheme = theme === 'dark' ? 'dark' : 'light';
        syncExcalidrawReactTheme(normalizedTheme);
        ensureHostThemeStyle();
        document.documentElement.classList.toggle('dark', normalizedTheme === 'dark');
        document.querySelectorAll('.excalidraw').forEach((root) => {
            root.classList.toggle('theme--dark', normalizedTheme === 'dark');
        });

        const api = window._excalidrawAPI;
        if (!api || typeof api.updateScene !== 'function') {
            _pendingHostTheme = normalizedTheme;
            return;
        }
        const currentState = typeof api.getAppState === 'function'
            ? api.getAppState()
            : null;
        // Excalidraw 的深色主题会给 canvas 应用 invert(93%) 滤镜。
        // 因此场景背景必须保持原始颜色（默认是白色），不能把它改成
        // #121212，否则会被滤镜再次反转成接近白色。旧版本曾写入
        // #121212，这里只对这个遗留值做一次迁移恢复。
        const legacyDarkBackground =
            typeof currentState?.viewBackgroundColor === 'string' &&
            currentState.viewBackgroundColor.toLowerCase() === '#121212';
        const alreadyApplied = currentState?.theme === normalizedTheme &&
            !legacyDarkBackground;
        if (alreadyApplied) {
            return;
        }
        _applyingHostTheme = true;
        try {
            const appState = { theme: normalizedTheme };
            if (legacyDarkBackground) {
                appState.viewBackgroundColor = '#ffffff';
            }
            api.updateScene({
                // UI 主题与场景背景是两个独立状态；只更新主题，交给
                // Excalidraw 自带滤镜把默认白色画布渲染成深色。
                appState,
                commitToHistory: false,
            });
        } finally {
            // Excalidraw writes localStorage during updateScene; keep the guard
            // active until that synchronous callback chain has completed.
            setTimeout(() => { _applyingHostTheme = false; }, 0);
        }
    };

    // Flutter 调用：将应用/系统主题作为新白板的默认主题。
    window.setHostTheme = function (theme) {
        const normalizedTheme = theme === 'dark' ? 'dark' : 'light';
        console.log('[PonyNotes] Host system appearance changed to ' + normalizedTheme);
        _forcedHostTheme = normalizedTheme;
        window.__ponynotesHostTheme = normalizedTheme;
        applyHostThemeToScene(normalizedTheme);
        if (!window._ponynotesHostThemeWatchdog) {
            window._ponynotesHostThemeWatchdog = setInterval(() => {
                if (_forcedHostTheme) applyHostThemeToScene(_forcedHostTheme);
            }, 500);
        }
    };

    const enforceHostTheme = (payload) => {
        if (_applyingHostTheme || !_forcedHostTheme) return;
        const sceneTheme = getPayloadTheme(payload);
        if (sceneTheme && sceneTheme !== _forcedHostTheme) {
            setTimeout(() => applyHostThemeToScene(_forcedHostTheme), 0);
        }
    };

    // ✅ 关键修复（数据丢失根因）：稳定 appState 助手必须在此处提前定义。
    // 原因：下方 waitForExcalidrawAndRestore() 会在 IIFE 同步执行阶段（远早于
    // 这些 const 原先所在的位置）就被调用；若白板 API 已预热（切回已打开过的
    // 白板），会同步进入 _restoreWhiteboardData → pickStableAppState，此时该
    // const 仍处于 TDZ（暂时性死区），抛出
    // "Cannot access 'pickStableAppState' before initialization"，导致整个恢复
    // 流程中断、elements 与 files(图片) 全部未注入 → 白板内容丢失。
    // 将定义提前到调用点之前可彻底消除该竞态。
    //
    // scrollX/scrollY 故意不包含在此集合中。
    // 原因同 whiteboard_collab_adapter.dart：每次 resize 反馈循环都会调整
    // scrollX/scrollY，若将其纳入 stableAppStateKeys，远端 appState 推送
    // 会把旧的坐标覆写到当前画布，造成漂移。
    const stableAppStateKeys = new Set([
        'gridModeEnabled',
        'gridSize',
        'theme',
        'viewBackgroundColor',
        'zoom',
        'zenModeEnabled',
    ]);

    const pickStableAppState = (appState) => {
        if (!appState || typeof appState !== 'object') {
            return {};
        }

        const stableState = {};
        for (const key of stableAppStateKeys) {
            if (Object.prototype.hasOwnProperty.call(appState, key)) {
                stableState[key] = appState[key];
            }
        }
        return stableState;
    };

    function _getSceneElementsForSync(fallbackValue) {
        const api = window._excalidrawAPI;
        if (api) {
            try {
                const elements = (
                    typeof api.getSceneElementsIncludingDeleted === 'function'
                        ? api.getSceneElementsIncludingDeleted()
                        : api.getSceneElements?.()
                );
                if (Array.isArray(elements)) {
                    return JSON.stringify(elements);
                }
            } catch (e) {
                console.warn('[PonyNotes] Failed to read elements including deleted, using storage value:', e);
            }
        }
        return fallbackValue;
    }

    const pendingFlutterStorageSyncs = new Map();
    const flutterStorageSyncTimers = new Map();
    const lastSentFlutterStorageValues = new Map();
    const flutterStorageSyncDelays = {
        excalidraw: 280,
        'excalidraw-state': 650,
        'excalidraw-files': 900,
        default: 500,
    };
    let pendingFilesSyncTimer = null;
    let pendingFilesSyncKey = null;

    function flutterStorageSyncDelayForKey(key) {
        if (key === 'excalidraw' || key.endsWith('_excalidraw')) {
            return flutterStorageSyncDelays.excalidraw;
        }
        if (key.endsWith('excalidraw-state')) {
            return flutterStorageSyncDelays['excalidraw-state'];
        }
        if (key.endsWith('excalidraw-files')) {
            return flutterStorageSyncDelays['excalidraw-files'];
        }
        return flutterStorageSyncDelays.default;
    }

    function flushFlutterStorageSync(key) {
        const payload = pendingFlutterStorageSyncs.get(key);
        if (!payload) return Promise.resolve();

        const timer = flutterStorageSyncTimers.get(key);
        if (timer) {
            clearTimeout(timer);
            flutterStorageSyncTimers.delete(key);
        }
        pendingFlutterStorageSyncs.delete(key);

        const value = typeof payload.valueProvider === 'function'
            ? payload.valueProvider()
            : payload.value;
        const lastValue = lastSentFlutterStorageValues.get(key);
        if (lastValue === value) {
            return Promise.resolve();
        }
        try {
            return Promise.resolve(window.flutter_inappwebview.callHandler(
                'localStorageOnSet',
                { key, value },
            )).then((result) => {
                lastSentFlutterStorageValues.set(key, value);
                return result;
            }).catch((error) => {
                // Do not acknowledge a failed bridge delivery. Keep the newest
                // value queued so iOS picker lifecycle pauses cannot turn into
                // a permanent "already sent" state.
                if (!pendingFlutterStorageSyncs.has(key)) {
                    pendingFlutterStorageSyncs.set(key, payload);
                    flutterStorageSyncTimers.set(key, setTimeout(
                        () => flushFlutterStorageSync(key),
                        250,
                    ));
                }
                throw error;
            });
        } catch (e) {
            return Promise.reject(e);
        }
    }

    async function flushAllFlutterStorageSyncs() {
        const pending = [];
        if (_iosImageSceneSyncTimer) {
            clearTimeout(_iosImageSceneSyncTimer);
            _iosImageSceneSyncTimer = null;
        }
        if (_iosImageSceneSyncPending) {
            pending.push(flushIOSImageSceneSync());
        }
        if (pendingFilesSyncTimer) {
            clearTimeout(pendingFilesSyncTimer);
            pendingFilesSyncTimer = null;
            pending.push(syncFilesFromScene(pendingFilesSyncKey, true));
        }
        for (const key of Array.from(pendingFlutterStorageSyncs.keys())) {
            pending.push(flushFlutterStorageSync(key));
        }
        await Promise.allSettled(pending);
        return true;
    }

    // Flutter 在本地白板销毁前调用，确保 elements/files 防抖队列先进入 Dart。
    window.__ponynotesFlushStorageSyncs = flushAllFlutterStorageSyncs;

    function scheduleFlutterStorageSync(key, value) {
        pendingFlutterStorageSyncs.set(
            key,
            typeof value === 'function' ? { key, valueProvider: value } : { key, value },
        );

        const existingTimer = flutterStorageSyncTimers.get(key);
        if (existingTimer) {
            clearTimeout(existingTimer);
        }

        flutterStorageSyncTimers.set(
            key,
            setTimeout(() => flushFlutterStorageSync(key), flutterStorageSyncDelayForKey(key)),
        );
    }

    window.addEventListener('pagehide', flushAllFlutterStorageSyncs);
    window.addEventListener('beforeunload', flushAllFlutterStorageSyncs);

    function syncFilesFromScene(key, immediate = false) {
        if (!window._excalidrawAPI) return Promise.resolve();

        try {
            const api = window._excalidrawAPI;
            let files = null;

            if (typeof api.getFiles === 'function') {
                files = api.getFiles();
            } else if (typeof api.getSceneElements === 'function') {
                const elements = api.getSceneElements();
                if (elements && Array.isArray(elements)) {
                    files = {};
                    elements.forEach(el => {
                        if (el.fileId && el.imageData) {
                            files[el.fileId] = {
                                id: el.fileId,
                                data: el.imageData,
                                created: Date.now(),
                                mimeType: el.mimeType || 'image/png'
                            };
                        }
                    });
                }
            }

            if (!files || Object.keys(files).length === 0) return Promise.resolve();

            if (_initPayload && _initPayload.files && typeof _initPayload.files === 'object') {
                for (const fileId of Object.keys(files)) {
                    const initFile = _initPayload.files[fileId];
                    if (initFile && initFile.url && typeof initFile.url === 'string' && initFile.url.startsWith('http')) {
                        files[fileId].url = initFile.url;
                    }
                }
            }

            const filesKey = key + '-files';
            const filesValue = JSON.stringify(files);
            scheduleFlutterStorageSync(filesKey, filesValue);
            return immediate ? flushFlutterStorageSync(filesKey) : Promise.resolve();
        } catch (e) {
            console.error('[PonyNotes] Failed to sync files:', e);
            return Promise.reject(e);
        }
    }

    function scheduleFilesSyncFromScene(key) {
        pendingFilesSyncKey = key;
        if (pendingFilesSyncTimer) {
            clearTimeout(pendingFilesSyncTimer);
        }
        pendingFilesSyncTimer = setTimeout(() => {
            pendingFilesSyncTimer = null;
            syncFilesFromScene(pendingFilesSyncKey);
        }, flutterStorageSyncDelays['excalidraw-files']);
    }

    // 创建隔离的localStorage代理
    const isolatedStorage = {
        getItem: function (key) {
            if (useMemoryStorage && memoryStorage.has(key)) {
                return memoryStorage.get(key);
            }
            if (useMemoryStorage) {
                return null;
            }
            return originalLocalStorage.getItem(scopedStorageKey(key));
        },

        setItem: function (key, value) {
            if (useMemoryStorage) {
                memoryStorage.set(key, String(value));
            } else {
                originalLocalStorage.setItem(scopedStorageKey(key), value);
            }
            if (key.endsWith('excalidraw-state')) {
                let state = value;
                if (typeof state === 'string') {
                    try { state = JSON.parse(state); } catch (e) { state = null; }
                }
                enforceHostTheme({ appState: state });
            }
            if (init) {
                scheduleFlutterStorageSync(
                    key,
                    key.endsWith('excalidraw') ? () => _getSceneElementsForSync(value) : value,
                );

                // 📸 关键修复：当 elements 更新时，自动捕获 files 并同步
                // Excalidraw 不会将 files 写入 localStorage，我们需要手动提取
                if (key.endsWith('excalidraw') && window._excalidrawAPI) {
                    scheduleFilesSyncFromScene(key);
                }
            }
        },

        removeItem: function (key) {
            if (useMemoryStorage) {
                memoryStorage.delete(key);
            } else {
                originalLocalStorage.removeItem(scopedStorageKey(key));
                originalLocalStorage.removeItem(key);
            }
            if (init) {
                window.flutter_inappwebview.callHandler('localStorageOnRemove', { key: key });
            }
        },

        clear: function () {
            if (useMemoryStorage) {
                memoryStorage.clear();
            } else {
                clearCurrentWhiteboardStorage();
            }
            if (init) {
                window.flutter_inappwebview.callHandler('localStorageOnClear');
            }
        },

        key: function (index) {
            if (useMemoryStorage) {
                return Array.from(memoryStorage.keys())[index] || null;
            }
            const key = scopedStorageKeys()[index];
            return key ? key.substring(storagePrefix.length) : null;
        },

        // ✅ 修复：返回正确的 length 值
        get length() {
            if (useMemoryStorage) {
                return memoryStorage.size;
            }
            return scopedStorageKeys().length;
        }
    };

    // 🔑 关键：用隔离的storage替换window.localStorage
    try {
        Object.defineProperty(window, 'localStorage', {
            get: function () {
                return isolatedStorage;
            },
            configurable: false
        });
        console.log(
            `[PonyNotes] ✅ localStorage bridge installed (${useMemoryStorage ? 'memory' : 'persistent'} mode)`,
        );
    } catch (e) {
        console.error('[PonyNotes] ❌ Failed to install localStorage isolation:', e);
    }

    clearCurrentWhiteboardStorage();

    // ✅ 关键修复：initData 现在返回加载的数据
    // 将数据保存到 _initPayload，用于后续恢复（不依赖 localStorage）
    try {
        _initPayload = await window.flutter_inappwebview.callHandler('initData');
        console.log('[PonyNotes] ✅ initData completed, payload:',
            _initPayload ? Object.keys(_initPayload) : 'null');
    } catch (e) {
        console.error('[PonyNotes] ❌ initData failed:', e);
        _initPayload = null;
    }

    init = true;

    // ✅ 关键修复：在 init=true 之后立即尝试恢复数据
    // 不再依赖 _safeEvalJs 的延迟调用，而是直接在 IIFE 中处理
    // 此时 localStorage 已被 initData 设置，且 _initPayload 已保存
    let _filesInjected = false;

    // 等待 Excalidraw API 就绪后立即恢复数据
    const waitForExcalidrawAndRestore = async () => {
        let attempts = 0;
        const maxAttempts = 100; // 最多等待 20 秒
        const interval = 200;

        while (attempts < maxAttempts) {
            const api = window.excalidrawAPI || window.__EXCALIDRAW_API__ ||
                window._excalidrawAPI || window.__xmGetExcalidrawAPI?.();
            if (api) {
                window._excalidrawAPI = api;
                installIOSImageDecodeRefresh(api);
                console.log('[PonyNotes] ✅ Excalidraw API captured, restoring data...');

                // 先应用宿主主题再恢复场景，避免恢复较大的白板数据期间露出白色首屏。
                if (_pendingHostTheme) {
                    applyHostThemeToScene(_pendingHostTheme);
                }

                if (!_filesInjected) {
                    _filesInjected = true;
                    try {
                        await _restoreWhiteboardData(api);
                        if (_pendingHostTheme) {
                            const pendingTheme = _pendingHostTheme;
                            _pendingHostTheme = null;
                            applyHostThemeToScene(pendingTheme);
                        }
                    } catch (e) {
                        console.error('[PonyNotes] ❌ Data restoration failed:', e);
                    }
                }
                return;
            }
            attempts++;
            await new Promise(resolve => setTimeout(resolve, interval));
        }
        console.error('[PonyNotes] ❌ Excalidraw API not found after max attempts');
    };

    // 启动异步恢复（不阻塞后续代码）
    waitForExcalidrawAndRestore();

    // =========================================================================
    // Excalidraw API 适配：导入 / 导出 / 数据加载
    // =========================================================================
    const waitForExcalidrawAPI = (maxAttempts = 60, interval = 150) =>
        new Promise((resolve, reject) => {
            let attempt = 0;
            const timer = setInterval(() => {
                attempt++;
                const api =
                    window.excalidrawAPI ||
                    window.__EXCALIDRAW_API__ ||
                    window._excalidrawAPI ||
                    window.__xmGetExcalidrawAPI?.();
                if (api) {
                    clearInterval(timer);
                    resolve(api);
                }
                if (attempt >= maxAttempts) {
                    clearInterval(timer);
                    reject(new Error('Excalidraw API not ready'));
                }
            }, interval);
        });

    const getSceneData = (api) => ({
        elements: api.getSceneElements?.() || [],
        appState: api.getAppState?.() || {},
        files: api.getFiles?.() || {},
    });

    const getRenderableElements = (elements) =>
        (elements || []).filter((element) => element && !element.isDeleted);

    const getSelectedElementIds = (appState) => {
        const selectedElementIds = appState?.selectedElementIds;
        if (!selectedElementIds || typeof selectedElementIds !== 'object') {
            return new Set();
        }
        return new Set(
            Object.entries(selectedElementIds)
                .filter(([, selected]) => Boolean(selected))
                .map(([id]) => id),
        );
    };

    const getSelectedGroupIds = (appState) => {
        const selectedGroupIds = appState?.selectedGroupIds;
        if (!selectedGroupIds || typeof selectedGroupIds !== 'object') {
            return new Set();
        }
        return new Set(
            Object.entries(selectedGroupIds)
                .filter(([, selected]) => Boolean(selected))
                .map(([id]) => id),
        );
    };

    const getActiveLinearElementId = (appState) =>
        appState?.selectedLinearElement?.elementId ||
        appState?.editingLinearElement?.elementId ||
        null;

    const isElementInSelectedGroup = (element, selectedGroupIds) =>
        (element?.groupIds || []).some((groupId) => selectedGroupIds.has(groupId));

    const collectSelectedElements = (appState, allElements) => {
        const selectedIds = getSelectedElementIds(appState);
        const activeLinearElementId = getActiveLinearElementId(appState);
        if (activeLinearElementId) {
            selectedIds.add(activeLinearElementId);
        }

        const selectedGroupIds = getSelectedGroupIds(appState);
        return allElements.filter(
            (element) =>
                selectedIds.has(element.id) ||
                isElementInSelectedGroup(element, selectedGroupIds),
        );
    };

    const collectElementDependencies = (element, exportIds) => {
        if (!element) {
            return;
        }
        if (element.containerId) {
            exportIds.add(element.containerId);
        }
        for (const boundElement of element.boundElements || []) {
            if (boundElement?.id) {
                exportIds.add(boundElement.id);
            }
        }
    };

    const expandSelectionDependencies = (selectedElements, allElements) => {
        const exportIds = new Set(selectedElements.map((element) => element.id));

        for (const element of selectedElements) {
            collectElementDependencies(element, exportIds);
        }

        for (const element of allElements) {
            if (exportIds.has(element.id)) {
                collectElementDependencies(element, exportIds);
            }
        }

        return allElements.filter((element) => exportIds.has(element.id));
    };

    const getClipboardSceneData = (api) => {
        const sceneData = getSceneData(api);
        const allElements = getRenderableElements(sceneData.elements);
        const selectedElements = collectSelectedElements(
            sceneData.appState,
            allElements,
        );

        if (!selectedElements.length) {
            return {
                ...sceneData,
                __ponynotesHasSelection: false,
                __ponynotesExportScope: 'all',
            };
        }

        return {
            ...sceneData,
            elements: expandSelectionDependencies(selectedElements, allElements),
            __ponynotesHasSelection: true,
            __ponynotesExportScope: 'selection',
        };
    };

    const hasConfirmedSelection = (sceneData) =>
        Boolean(sceneData?.__ponynotesHasSelection);

    const getExportScale = () => {
        const ratio = Number(window.devicePixelRatio || 1);
        return Math.max(2, Math.min(4, ratio || 1));
    };

    const buildExportOptions = (sceneData, scale = getExportScale()) => ({
        elements: getRenderableElements(sceneData.elements),
        appState: {
            ...(sceneData.appState || {}),
            exportBackground: true,
            shouldAddWatermark: false,
        },
        files: sceneData.files || {},
        exportPadding: 16,
        getDimensions: (width, height) => ({
            width: Math.ceil(width * scale),
            height: Math.ceil(height * scale),
            scale,
        }),
    });

    const blobToDataUrl = (blob) =>
        new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onloadend = () => resolve(reader.result);
            reader.onerror = () => reject(new Error('FileReader failed'));
            reader.readAsDataURL(blob);
        });

    const canvasToBlob = (canvas, mimeType = 'image/png', quality = 1) =>
        new Promise((resolve, reject) => {
            if (!canvas) {
                reject(new Error('Canvas is empty'));
                return;
            }
            canvas.toBlob((blob) => {
                if (blob) {
                    resolve(blob);
                } else {
                    reject(new Error('Canvas toBlob returned empty result'));
                }
            }, mimeType, quality);
        });

    const serializeSvgResult = async (svg) => {
        if (!svg) {
            return null;
        }
        if (typeof svg === 'string') {
            return svg.includes('<svg') ? svg : null;
        }
        if (svg instanceof SVGSVGElement || svg instanceof Element) {
            return new XMLSerializer().serializeToString(svg);
        }
        if (svg instanceof Blob) {
            const text = await svg.text();
            return text.includes('<svg') ? text : null;
        }
        return null;
    };

    const createHighQualityPngBlob = async (sceneData, exportSettings = {}) => {
        const allowVisibleCanvasFallback =
            exportSettings.allowVisibleCanvasFallback !== false;
        const scale = getExportScale();
        const options = buildExportOptions(sceneData, scale);

        if (!options.elements.length) {
            throw new Error('No renderable elements to export');
        }

        if (window.ExcalidrawLib?.exportToCanvas) {
            const canvas = await window.ExcalidrawLib.exportToCanvas(options);
            return canvasToBlob(canvas, 'image/png', 1);
        }

        if (typeof window.exportToPng === 'function') {
            const result = await window.exportToPng(options);
            if (result instanceof Blob) {
                return result;
            }
        }

        if (typeof window.exportToImage === 'function') {
            const result = await window.exportToImage({
                ...options,
                mimeType: 'image/png',
            });
            if (result instanceof Blob) {
                return result;
            }
            if (typeof result === 'string' && result.startsWith('data:image/png')) {
                return await (await fetch(result)).blob();
            }
        }

        if (!allowVisibleCanvasFallback) {
            throw new Error('Selected export canvas fallback is disabled');
        }

        const visibleCanvas = document.querySelector('canvas.excalidraw__canvas');
        if (!visibleCanvas) {
            throw new Error('No visible canvas fallback available');
        }

        const fallbackScale = getExportScale();
        const scaledCanvas = document.createElement('canvas');
        scaledCanvas.width = Math.ceil(visibleCanvas.width * fallbackScale);
        scaledCanvas.height = Math.ceil(visibleCanvas.height * fallbackScale);
        const context = scaledCanvas.getContext('2d');
        context.imageSmoothingEnabled = true;
        context.imageSmoothingQuality = 'high';
        context.drawImage(visibleCanvas, 0, 0, scaledCanvas.width, scaledCanvas.height);
        return canvasToBlob(scaledCanvas, 'image/png', 1);
    };

    const createHighQualitySvgString = async (sceneData) => {
        const options = buildExportOptions(sceneData, 1);

        if (!options.elements.length) {
            throw new Error('No renderable elements to export');
        }

        if (typeof window.exportToSvg === 'function') {
            const svg = await window.exportToSvg(options);
            const svgString = await serializeSvgResult(svg);
            if (svgString) {
                return svgString;
            }
        }

        if (window.ExcalidrawLib?.exportToSvg) {
            const svg = await window.ExcalidrawLib.exportToSvg(options);
            const svgString = await serializeSvgResult(svg);
            if (svgString) {
                return svgString;
            }
        }

        if (typeof window.exportToImage === 'function') {
            const result = await window.exportToImage({
                ...options,
                mimeType: 'image/svg+xml',
            });
            const svgString = await serializeSvgResult(result);
            if (svgString) {
                return svgString;
            }
        }

        throw new Error('True SVG export is not available');
    };

    const clipboardSupports = (mimeType) => {
        if (typeof window.ClipboardItem?.supports === 'function') {
            return window.ClipboardItem.supports(mimeType);
        }
        return mimeType === 'image/png' || mimeType === 'text/html';
    };

    const writePngBlobToClipboard = async (blob, originalWrite) => {
        if (!navigator.clipboard || !window.ClipboardItem || !originalWrite) {
            throw new Error('Clipboard image write is not available');
        }
        const item = new ClipboardItem({ 'image/png': blob });
        await originalWrite([item]);
    };

    const bytesToBase64 = (bytes) => {
        let binary = '';
        const chunkSize = 0x8000;
        for (let index = 0; index < bytes.length; index += chunkSize) {
            const chunk = bytes.subarray(index, index + chunkSize);
            binary += String.fromCharCode(...chunk);
        }
        return btoa(binary);
    };

    const svgStringToDataUrl = (svgString) => {
        const encoded = new TextEncoder().encode(svgString);
        return `data:image/svg+xml;base64,${bytesToBase64(encoded)}`;
    };

    const buildSvgClipboardHtml = (svgString) => {
        const dataUrl = svgStringToDataUrl(svgString);
        return [
            '<!doctype html>',
            '<html><body>',
            `<img data-ponynotes-whiteboard-svg="true" src="${dataUrl}" />`,
            '</body></html>',
        ].join('');
    };

    const writeSvgStringToClipboard = async (
        svgString,
        originalWrite,
        sceneData,
        exportSettings = {},
    ) => {
        if (!navigator.clipboard || !window.ClipboardItem || !originalWrite) {
            throw new Error('Clipboard SVG write is not available');
        }

        const clipboardPayload = {};

        if (clipboardSupports('image/png')) {
            try {
                clipboardPayload['image/png'] = await createHighQualityPngBlob(
                    sceneData,
                    exportSettings,
                );
            } catch (error) {
                console.warn('[PonyNotes] SVG clipboard PNG fallback failed:', error);
            }
        }

        if (clipboardSupports('text/html')) {
            clipboardPayload['text/html'] = new Blob(
                [buildSvgClipboardHtml(svgString)],
                { type: 'text/html' },
            );
        }

        if (clipboardSupports('image/svg+xml')) {
            clipboardPayload['image/svg+xml'] = new Blob([svgString], {
                type: 'image/svg+xml',
            });
        }

        if (!Object.keys(clipboardPayload).length) {
            throw new Error('No supported clipboard format for SVG export');
        }

        await originalWrite([new ClipboardItem(clipboardPayload)]);
    };

    const installContextMenuFontPatch = () => {
        if (window.__ponynotesContextMenuFontPatchInstalled) {
            return;
        }

        const isWindows = /Windows/i.test(window.navigator?.userAgent || '');
        const menuFontFamily = isWindows
            ? '"Segoe UI", "Microsoft YaHei UI", "Microsoft YaHei", Arial, sans-serif'
            : '-apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei UI", Arial, sans-serif';
        const smoothingRules = isWindows
            ? `
    -webkit-font-smoothing: auto;
    -moz-osx-font-smoothing: auto;
    text-rendering: auto;
`
            : `
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    text-rendering: optimizeLegibility;
`;

        const style = document.createElement('style');
        style.setAttribute('data-ponynotes-context-menu-font-patch', 'true');
        style.textContent = `
.excalidraw [role="menu"],
.excalidraw [role="menu"] *,
.excalidraw [role="menuitem"],
.excalidraw [role="menuitem"] *,
.excalidraw .context-menu,
.excalidraw .context-menu *,
.excalidraw .context-menu-item,
.excalidraw .context-menu-item *,
.excalidraw .context-menu-item__label,
.excalidraw .context-menu-item__shortcut,
.excalidraw .dropdown-menu,
.excalidraw .dropdown-menu * {
    ${smoothingRules}
    font-family: ${menuFontFamily};
    font-size: ${isWindows ? '15px' : '13px'};
    font-weight: ${isWindows ? 600 : 500};
    line-height: 1.45;
    letter-spacing: 0;
    text-shadow: none;
}

.excalidraw .popover.context-menu-popover,
.excalidraw .context-menu-popover {
    background: transparent !important;
    border: none !important;
    box-shadow: none !important;
    filter: none !important;
    backdrop-filter: none !important;
    -webkit-backdrop-filter: none !important;
    min-width: 0 !important;
    min-height: 0 !important;
    width: auto !important;
    height: auto !important;
    overflow: visible !important;
}

.excalidraw .context-menu,
.excalidraw [role="menu"] {
    filter: none !important;
    backdrop-filter: none !important;
    -webkit-backdrop-filter: none !important;
    opacity: 1 !important;
    backface-visibility: visible !important;
    perspective: none !important;
    will-change: auto !important;
    contain: none !important;
    transform-style: flat !important;
}

.excalidraw .context-menu-item {
    color: rgba(17, 24, 39, 0.96);
}

.excalidraw .context-menu-item .context-menu-item__shortcut {
    font-size: ${isWindows ? '13px' : '11px'};
    font-weight: ${isWindows ? 500 : 500};
    color: rgba(55, 65, 81, 0.88);
}
`;
        document.head.appendChild(style);
        window.__ponynotesContextMenuFontPatchInstalled = true;
    };

    const base64ToBlob = (base64, mimeType) => {
        const binary = atob(base64 || '');
        const bytes = new Uint8Array(binary.length);
        for (let index = 0; index < binary.length; index++) {
            bytes[index] = binary.charCodeAt(index);
        }
        return new Blob([bytes], { type: mimeType });
    };

    const buildClipboardReadItem = (payload) => {
        const entries = {};

        if (payload?.imageBase64 && payload?.imageMimeType) {
            entries[payload.imageMimeType] = base64ToBlob(
                payload.imageBase64,
                payload.imageMimeType,
            );
        }

        if (payload?.html) {
            entries['text/html'] = new Blob([payload.html], {
                type: 'text/html',
            });
        }

        if (payload?.plainText) {
            entries['text/plain'] = new Blob([payload.plainText], {
                type: 'text/plain',
            });
        }

        const types = Object.keys(entries);
        if (!types.length) {
            return null;
        }

        return {
            types,
            async getType(type) {
                const blob = entries[type];
                if (!blob) {
                    throw new DOMException(
                        `Clipboard item does not contain ${type}`,
                        'NotFoundError',
                    );
                }
                return blob;
            },
        };
    };

    const installContextMenuPastePositionPatch = () => {
        if (window.__ponynotesContextMenuPastePositionPatchInstalled) {
            return;
        }

        const maxAgeMs = 15000;

        const isInsideExcalidraw = (target) =>
            !!target?.closest?.('.excalidraw, .excalidraw-container');

        const saveContextMenuPosition = (event) => {
            if (!isInsideExcalidraw(event.target)) {
                return;
            }

            window.__ponynotesContextMenuPastePosition = {
                clientX: event.clientX,
                clientY: event.clientY,
                time: Date.now(),
            };
        };

        const isPasteMenuItem = (target) => {
            const item = target?.closest?.(
                '[role="menuitem"], .context-menu-item, button, [data-testid]',
            );
            if (!item) {
                return false;
            }

            const text = (item.textContent || '')
                .replace(/\s+/g, ' ')
                .trim()
                .toLowerCase();

            if (!text) {
                return false;
            }

            const looksLikePaste =
                text.startsWith('粘贴') ||
                text.startsWith('paste') ||
                (text.includes('ctrl+v') && !text.includes('style'));

            const isOtherPasteCommand =
                text.includes('style') ||
                text.includes('样式') ||
                text.includes('plaintext') ||
                text.includes('纯文本');

            return looksLikePaste && !isOtherPasteCommand;
        };

        const restoreContextMenuPastePosition = () => {
            const position = window.__ponynotesContextMenuPastePosition;
            if (!position || Date.now() - position.time > maxAgeMs) {
                return;
            }

            const canvas = document.querySelector('.excalidraw canvas');
            const target =
                canvas ||
                document.querySelector('.excalidraw') ||
                document.elementFromPoint(position.clientX, position.clientY) ||
                document;
            const eventInit = {
                bubbles: true,
                cancelable: true,
                clientX: position.clientX,
                clientY: position.clientY,
                screenX: position.clientX,
                screenY: position.clientY,
            };

            try {
                target.dispatchEvent(new PointerEvent('pointermove', {
                    ...eventInit,
                    pointerId: 1,
                    pointerType: 'mouse',
                    isPrimary: true,
                }));
            } catch (error) {
                target.dispatchEvent(new MouseEvent('mousemove', eventInit));
            }

            target.dispatchEvent(new MouseEvent('mousemove', eventInit));

            if (canvas && !window.__ponynotesElementFromPointForPasteActive) {
                const originalElementFromPoint =
                    document.elementFromPoint.bind(document);
                window.__ponynotesElementFromPointForPasteActive = true;
                document.elementFromPoint = function (x, y) {
                    const isContextPastePoint =
                        Math.abs(x - position.clientX) <= 1 &&
                        Math.abs(y - position.clientY) <= 1;
                    if (isContextPastePoint) {
                        const element = originalElementFromPoint(x, y);
                        if (!(element instanceof HTMLCanvasElement)) {
                            return canvas;
                        }
                    }
                    return originalElementFromPoint(x, y);
                };

                setTimeout(() => {
                    document.elementFromPoint = originalElementFromPoint;
                    window.__ponynotesElementFromPointForPasteActive = false;
                }, 1500);
            }
        };

        const handleMenuPointerDown = (event) => {
            if (!isPasteMenuItem(event.target)) {
                return;
            }
            restoreContextMenuPastePosition();
        };

        document.addEventListener('contextmenu', saveContextMenuPosition, true);
        document.addEventListener('pointerdown', handleMenuPointerDown, true);
        document.addEventListener('mousedown', handleMenuPointerDown, true);

        window.__ponynotesContextMenuPastePositionPatchInstalled = true;
        console.log('[PonyNotes] Context menu paste position patch installed');
    };

    const installSafeClipboardReadPatch = (clipboard, originalRead) => {
        if (
            !clipboard ||
            !originalRead ||
            window.__ponynotesClipboardReadPatchInstalled
        ) {
            return;
        }

        const isWindows = /Windows/i.test(window.navigator?.userAgent || '');
        if (!isWindows || !window.flutter_inappwebview?.callHandler) {
            return;
        }

        clipboard.read = async function () {
            if (window.__ponynotesClipboardReadActive) {
                throw new DOMException('Clipboard read is already active', 'AbortError');
            }

            try {
                window.__ponynotesClipboardReadActive = true;
                const payload = await window.flutter_inappwebview.callHandler(
                    'readWhiteboardClipboard',
                );
                const item = buildClipboardReadItem(payload);
                if (!item) {
                    throw new DOMException('Clipboard is empty', 'NotFoundError');
                }
                return [item];
            } catch (error) {
                console.warn('[PonyNotes] Safe clipboard read failed:', error);
                throw error instanceof DOMException
                    ? error
                    : new DOMException('Safe clipboard read failed', 'NotAllowedError');
            } finally {
                window.__ponynotesClipboardReadActive = false;
            }
        };

        window.__ponynotesClipboardReadPatchInstalled = true;
        console.log('[PonyNotes] Safe clipboard read patch installed');
    };

    const installHighQualityClipboardPatch = () => {
        const clipboard = navigator.clipboard;
        if (!clipboard) {
            return;
        }

        const originalRead = clipboard.read?.bind(clipboard);
        installSafeClipboardReadPatch(clipboard, originalRead);

        if (window.__ponynotesClipboardQualityPatchInstalled) {
            return;
        }

        const originalWrite = clipboard.write?.bind(clipboard);
        const originalWriteText = clipboard.writeText?.bind(clipboard);

        try {
            if (originalWrite) {
                clipboard.write = async function (items) {
                    if (window.__ponynotesClipboardQualityWriteActive) {
                        return originalWrite(items);
                    }

                    const types = (items || []).flatMap((item) =>
                        Array.from(item?.types || []),
                    );
                    const shouldUpgradePng = types.includes('image/png');
                    const shouldUpgradeSvg = types.includes('image/svg+xml');

                    if (!shouldUpgradePng && !shouldUpgradeSvg) {
                        return originalWrite(items);
                    }

                    try {
                        window.__ponynotesClipboardQualityWriteActive = true;
                        const api = await waitForExcalidrawAPI(12, 50);
                        const sceneData = getClipboardSceneData(api);

                        if (!hasConfirmedSelection(sceneData)) {
                            return originalWrite(items);
                        }

                        if (shouldUpgradeSvg) {
                            const svgString = await createHighQualitySvgString(sceneData);
                            return await writeSvgStringToClipboard(
                                svgString,
                                originalWrite,
                                sceneData,
                                { allowVisibleCanvasFallback: false },
                            );
                        }

                        const pngBlob = await createHighQualityPngBlob(sceneData, {
                            allowVisibleCanvasFallback: false,
                        });
                        return await writePngBlobToClipboard(pngBlob, originalWrite);
                    } catch (error) {
                        console.warn('[PonyNotes] High quality clipboard write failed:', error);
                        if (shouldUpgradeSvg) {
                            throw error;
                        }
                        return originalWrite(items);
                    } finally {
                        window.__ponynotesClipboardQualityWriteActive = false;
                    }
                };
            }

            if (originalWriteText) {
                clipboard.writeText = async function (text) {
                    const isSvgText =
                        typeof text === 'string' &&
                        text.trimStart().startsWith('<svg');
                    if (!isSvgText || window.__ponynotesClipboardQualityWriteActive) {
                        return originalWriteText(text);
                    }

                    try {
                        window.__ponynotesClipboardQualityWriteActive = true;
                        const api = await waitForExcalidrawAPI(12, 50);
                        const sceneData = getClipboardSceneData(api);
                        if (!hasConfirmedSelection(sceneData)) {
                            return originalWriteText(text);
                        }
                        const svgString = await createHighQualitySvgString(sceneData);
                        return await writeSvgStringToClipboard(
                            svgString,
                            originalWrite,
                            sceneData,
                            { allowVisibleCanvasFallback: false },
                        );
                    } catch (error) {
                        console.warn('[PonyNotes] High quality SVG clipboard failed:', error);
                        throw error;
                    } finally {
                        window.__ponynotesClipboardQualityWriteActive = false;
                    }
                };
            }

            window.__ponynotesClipboardQualityPatchInstalled = true;
            console.log('[PonyNotes] High quality clipboard patch installed');
        } catch (error) {
            console.warn('[PonyNotes] Failed to install clipboard quality patch:', error);
        }
    };

    installContextMenuFontPatch();
    installContextMenuPastePositionPatch();
    installHighQualityClipboardPatch();
    setTimeout(installContextMenuFontPatch, 500);
    setTimeout(installContextMenuPastePositionPatch, 500);
    setTimeout(installHighQualityClipboardPatch, 500);
    setTimeout(installContextMenuFontPatch, 1500);
    setTimeout(installContextMenuPastePositionPatch, 1500);
    setTimeout(installHighQualityClipboardPatch, 1500);

    // Flutter 调用：导出
    window.exportExcalidraw = async function (format = 'png') {
        try {
            const api = await waitForExcalidrawAPI();

            console.log('[PonyNotes] 开始导出，格式:', format);

            // 全面检查所有可能的导出API
            const exportAPIs = {
                'window.exportToPng': typeof window.exportToPng,
                'window.exportToSvg': typeof window.exportToSvg,
                'window.exportToImage': typeof window.exportToImage,
                'window.ExcalidrawLib': typeof window.ExcalidrawLib,
                'window.Excalidraw': typeof window.Excalidraw,
            };

            console.log('[PonyNotes] 检查可用的导出方法:', exportAPIs);

            // 如果ExcalidrawLib存在，检查它的方法
            if (window.ExcalidrawLib) {
                console.log('[PonyNotes] ExcalidrawLib 的方法:', Object.keys(window.ExcalidrawLib));
            }

            if (format === 'png') {
                // 获取场景数据
                const sceneData = getSceneData(api);
                console.log('[PonyNotes] 场景数据:', {
                    elementsCount: sceneData.elements?.length,
                    filesCount: Object.keys(sceneData.files || {}).length,
                });

                // 方案1: 使用 window.exportToPng
                try {
                    const pngBlob = await createHighQualityPngBlob(sceneData);
                    const dataUrl = await blobToDataUrl(pngBlob);
                    window.flutter_inappwebview?.callHandler('onExport', {
                        format: 'png',
                        data: dataUrl,
                    });
                    console.log('[PonyNotes] High quality PNG export succeeded');
                    return;
                } catch (e) {
                    console.warn('[PonyNotes] High quality PNG export failed:', e);
                }

                if (typeof window.exportToPng === 'function') {
                    console.log('[PonyNotes] 方案1: 使用 window.exportToPng');
                    try {
                        const blob = await window.exportToPng({
                            elements: sceneData.elements,
                            appState: sceneData.appState,
                            files: sceneData.files,
                        });

                        if (blob) {
                            const dataUrl = await new Promise((resolve, reject) => {
                                const reader = new FileReader();
                                reader.onloadend = () => resolve(reader.result);
                                reader.onerror = () => reject(new Error('FileReader 错误'));
                                reader.readAsDataURL(blob);
                            });

                            window.flutter_inappwebview?.callHandler('onExport', {
                                format: 'png',
                                data: dataUrl,
                            });
                            console.log('[PonyNotes] ✅ PNG 导出成功（方案1）');
                            return;
                        }
                    } catch (e) {
                        console.warn('[PonyNotes] 方案1失败:', e);
                    }
                }

                // 方案2: 使用 ExcalidrawLib.exportToCanvas
                if (window.ExcalidrawLib && window.ExcalidrawLib.exportToCanvas) {
                    console.log('[PonyNotes] 方案2: 使用 ExcalidrawLib.exportToCanvas');
                    try {
                        const canvas = await window.ExcalidrawLib.exportToCanvas({
                            elements: sceneData.elements,
                            appState: sceneData.appState,
                            files: sceneData.files,
                        });

                        if (canvas) {
                            const dataUrl = canvas.toDataURL('image/png', 0.95);
                            window.flutter_inappwebview?.callHandler('onExport', {
                                format: 'png',
                                data: dataUrl,
                            });
                            console.log('[PonyNotes] ✅ PNG 导出成功（方案2）');
                            return;
                        }
                    } catch (e) {
                        console.warn('[PonyNotes] 方案2失败:', e);
                    }
                }

                // 方案3: 使用 exportToImage
                if (typeof window.exportToImage === 'function') {
                    console.log('[PonyNotes] 方案3: 使用 window.exportToImage');
                    try {
                        const result = await window.exportToImage({
                            elements: sceneData.elements,
                            appState: sceneData.appState,
                            files: sceneData.files,
                            mimeType: 'image/png',
                        });

                        if (result) {
                            let dataUrl;
                            if (typeof result === 'string') {
                                dataUrl = result;
                            } else if (result instanceof Blob) {
                                dataUrl = await new Promise((resolve, reject) => {
                                    const reader = new FileReader();
                                    reader.onloadend = () => resolve(reader.result);
                                    reader.onerror = () => reject(new Error('FileReader 错误'));
                                    reader.readAsDataURL(result);
                                });
                            }

                            if (dataUrl) {
                                window.flutter_inappwebview?.callHandler('onExport', {
                                    format: 'png',
                                    data: dataUrl,
                                });
                                console.log('[PonyNotes] ✅ PNG 导出成功（方案3）');
                                return;
                            }
                        }
                    } catch (e) {
                        console.warn('[PonyNotes] 方案3失败:', e);
                    }
                }

                // 方案4: 回退 - 直接使用canvas（可能不完整）
                console.log('[PonyNotes] ⚠️ 方案4: 使用当前可见canvas（内容可能不完整）');
                const canvas = document.querySelector('canvas.excalidraw__canvas');
                if (canvas) {
                    console.log('[PonyNotes] Canvas尺寸:', canvas.width, 'x', canvas.height);

                    const dataUrl = canvas.toDataURL('image/png', 0.95);
                    window.flutter_inappwebview?.callHandler('onExport', {
                        format: 'png',
                        data: dataUrl,
                    });
                    console.log('[PonyNotes] ⚠️ PNG 导出完成（仅可见区域，请确保滚动查看所有内容）');
                    return;
                }

                throw new Error('所有PNG导出方案都失败了');
            }

            if (format === 'svg') {
                // 获取场景数据
                const sceneData = getSceneData(api);

                // 检查是否有全局的exportToSvg函数
                try {
                    const svgString = await createHighQualitySvgString(sceneData);
                    window.flutter_inappwebview?.callHandler('onExport', {
                        format: 'svg',
                        data: svgString,
                    });
                    console.log('[PonyNotes] High quality SVG export succeeded');
                    return;
                } catch (e) {
                    console.warn('[PonyNotes] High quality SVG export failed:', e);
                }

                if (typeof window.exportToSvg === 'function') {
                    console.log('[PonyNotes] 使用 window.exportToSvg');
                    const svg = await window.exportToSvg({
                        elements: sceneData.elements,
                        appState: sceneData.appState,
                        files: sceneData.files,
                    });

                    if (!svg) {
                        throw new Error('exportToSvg 返回空结果');
                    }

                    // 序列化SVG为字符串
                    let svgString;
                    if (typeof svg === 'string') {
                        svgString = svg;
                    } else if (svg instanceof SVGSVGElement || svg instanceof Element) {
                        const serializer = new XMLSerializer();
                        svgString = serializer.serializeToString(svg);
                    } else if (svg instanceof Blob) {
                        svgString = await new Promise((resolve, reject) => {
                            const reader = new FileReader();
                            reader.onloadend = () => {
                                if (reader.result) {
                                    resolve(reader.result);
                                } else {
                                    reject(new Error('FileReader 读取失败'));
                                }
                            };
                            reader.onerror = () => reject(new Error('FileReader 读取错误'));
                            reader.readAsText(svg);
                        });
                    } else {
                        throw new Error(`exportToSvg 返回了未知类型: ${typeof svg}`);
                    }

                    console.log('[PonyNotes] SVG 字符串长度:', svgString.length);

                    window.flutter_inappwebview?.callHandler('onExport', {
                        format: 'svg',
                        data: svgString,
                    });
                    console.log('[PonyNotes] SVG 导出成功');
                    return;
                }

                // 回退方案1：尝试使用 exportToImage 导出SVG
                console.log('[PonyNotes] 回退方案1：尝试使用 window.exportToImage');
                if (typeof window.exportToImage === 'function') {
                    try {
                        const result = await window.exportToImage({
                            elements: sceneData.elements,
                            appState: sceneData.appState,
                            files: sceneData.files,
                            mimeType: 'image/svg+xml',
                        });

                        if (result) {
                            let svgString;
                            if (typeof result === 'string') {
                                svgString = result;
                            } else if (result instanceof Blob) {
                                svgString = await new Promise((resolve, reject) => {
                                    const reader = new FileReader();
                                    reader.onloadend = () => resolve(reader.result || '');
                                    reader.onerror = () => reject(new Error('FileReader 读取错误'));
                                    reader.readAsText(result);
                                });
                            } else if (result instanceof SVGSVGElement || result instanceof Element) {
                                const serializer = new XMLSerializer();
                                svgString = serializer.serializeToString(result);
                            }

                            if (svgString) {
                                console.log('[PonyNotes] SVG 导出成功（使用exportToImage）, 长度:', svgString.length);
                                window.flutter_inappwebview?.callHandler('onExport', {
                                    format: 'svg',
                                    data: svgString,
                                });
                                return;
                            }
                        }
                    } catch (e) {
                        console.warn('[PonyNotes] exportToImage 失败:', e.message);
                    }
                }

                // 回退方案2：使用PNG嵌入SVG（不理想但可用）
                console.log('[PonyNotes] 回退方案2：将PNG嵌入SVG');
                const canvas = document.querySelector('canvas.excalidraw__canvas');
                if (canvas) {
                    const pngDataUrl = canvas.toDataURL('image/png', 0.95);
                    const width = canvas.width;
                    const height = canvas.height;

                    // 创建包含PNG的SVG
                    const svgString = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" 
     width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <title>Excalidraw Export</title>
  <desc>Exported from PonyNotes Whiteboard</desc>
  <image width="${width}" height="${height}" xlink:href="${pngDataUrl}"/>
</svg>`;

                    console.log('[PonyNotes] SVG生成成功（PNG嵌入方式）, 长度:', svgString.length);
                    window.flutter_inappwebview?.callHandler('onExport', {
                        format: 'svg',
                        data: svgString,
                    });
                    return;
                }

                throw new Error('所有SVG导出方案都失败了');
            }

            if (format === 'ponynotes' || format === 'excalidraw' || format === 'json') {
                const data = getSceneData(api);
                console.log('[PonyNotes] 导出场景数据, elements:', data.elements?.length);
                window.flutter_inappwebview?.callHandler('onExport', {
                    format: 'ponynotes',
                    data,
                });
                return;
            }

            window.flutter_inappwebview?.callHandler('onExportError', {
                message: `不支持的导出格式: ${format}`,
            });
        } catch (e) {
            console.error('[PonyNotes] exportExcalidraw failed', e);
            window.flutter_inappwebview?.callHandler('onExportError', {
                message: e?.message || String(e),
            });
        }
    };

    // Flutter 调用：载入数据
    window.loadExcalidrawData = async function (data, options = {}) {
        try {
            const api = await waitForExcalidrawAPI();
            const currentElements = typeof api.getSceneElements === 'function'
                ? api.getSceneElements()
                : [];
            if (options.preserveLocalSceneForBlankData === true &&
                isBlankScenePayload(data) && currentElements.length > 0) {
                console.warn(
                    '[PonyNotes] Preserved local scene from late blank initial data',
                );
                if (_forcedHostTheme) applyHostThemeToScene(_forcedHostTheme);
                return;
            }
            _initPayload = data || {};
            if (_forcedHostTheme) applyHostThemeToScene(_forcedHostTheme);
            await _restoreWhiteboardData(api);
            if (_forcedHostTheme) applyHostThemeToScene(_forcedHostTheme);
        } catch (e) {
            console.error('[PonyNotes] loadExcalidrawData failed', e);
        }
    };

    /**
     * ✅ 关键修复：白板数据恢复函数
     * 整合了 elements 恢复和文件注入逻辑
     */
    async function _restoreWhiteboardData(api) {
        try {
            console.log('[PonyNotes] 🔄 Starting whiteboard data restoration...');

            // 1. 恢复场景 (elements & appState)
            if (_initPayload) {
                const elements = _initPayload.elements || _initPayload.excalidraw;
                const appState = _initPayload.appState || _initPayload['excalidraw-state'];

                let elementsToRestore = elements;
                if (typeof elements === 'string') {
                    try { elementsToRestore = JSON.parse(elements); } catch (e) { }
                }

                // 初始数据是异步到达的。用户可能已经在当前 WebView 插入了图片，
                // 此时不能再用旧 payload 的全量 elements 覆盖本地新编辑。
                // 以元素版本合并，保留当前场景中尚未出现在 payload 的图片/编辑。
                if (Array.isArray(elementsToRestore) &&
                    typeof api.getSceneElementsIncludingDeleted === 'function') {
                    const currentElements = api.getSceneElementsIncludingDeleted() || [];
                    if (currentElements.length > 0) {
                        const payloadChanges = elementsToRestore
                            .filter((element) => element && element.id)
                            .map((element) => ({ id: element.id, element }));
                        elementsToRestore = _reconcileElements(
                            currentElements.slice(),
                            payloadChanges,
                        );
                        if (elementsToRestore.length !== currentElements.length ||
                            payloadChanges.length !== currentElements.length) {
                            console.warn(
                                '[PonyNotes] Preserved local edits while applying initial data: ' +
                                'current=' + currentElements.length +
                                ', payload=' + payloadChanges.length,
                            );
                        }
                    }
                }

                let appStateToRestore = appState;
                if (typeof appState === 'string') {
                    try { appStateToRestore = JSON.parse(appState); } catch (e) { }
                }
                appStateToRestore = pickStableAppState(appStateToRestore);
                // 场景数据可能保存了上一次会话的主题。私有白板主题由
                // Flutter 宿主决定，恢复时直接覆盖主题和画布背景，避免先
                // 绘制历史浅色再异步切回当前系统深色造成黑白闪烁。
                if (_forcedHostTheme) {
                    appStateToRestore.theme = _forcedHostTheme;
                    // 兼容旧版本曾保存的深色背景。正常数据的背景颜色
                    // 保持不变，由 Excalidraw 的主题滤镜负责深色显示。
                    if (typeof appStateToRestore.viewBackgroundColor === 'string' &&
                        appStateToRestore.viewBackgroundColor.toLowerCase() === '#121212') {
                        appStateToRestore.viewBackgroundColor = '#ffffff';
                    }
                }

                if (elementsToRestore || appStateToRestore) {
                    console.log('[PonyNotes] 🎨 Applying scene from payload');
                    api.updateScene({
                        elements: elementsToRestore || [],
                        appState: appStateToRestore || {},
                        commitToHistory: false
                    });
                }
            }

            // 2. 注入文件
            await _injectFilesFromStorage(api);

            if (_initPayload && Array.isArray(_initPayload._pendingElements) && _initPayload._pendingElements.length) {
                const pending = _initPayload._pendingElements;
                _initPayload._pendingElements = [];
                await window.pushWhiteboardElements(pending);
            }

            console.log('[PonyNotes] ✅ Restoration finished');
        } catch (e) {
            console.error('[PonyNotes] ❌ Failed to restore whiteboard data:', e);
        }
    }

    /**
     * 从存储加载并注入文件
     */
    async function _injectFilesFromStorage(api) {
        let filesMap = null;
        if (_initPayload) {
            filesMap = _initPayload.files || _initPayload['excalidraw-files'];
            if (typeof filesMap === 'string') {
                try {
                    filesMap = JSON.parse(filesMap);
                } catch (e) {
                    console.error('[PonyNotes] ❌ Failed to parse files from payload:', e);
                }
            }
        }

        if (filesMap) {
            await _injectFiles(api, filesMap);
        }
    }

    /**
     * 注入文件到 Excalidraw，处理 dataURL 和云端下载
     */
    async function _injectFiles(api, filesMap) {
        if (!filesMap || typeof filesMap !== 'object') return;

        const entries = Object.entries(filesMap);
        if (entries.length === 0) return;

        console.log('[PonyNotes] 📸 Injecting ' + entries.length + ' files...');
        const toAdd = [];
        const toFetch = [];

        for (const [id, data] of entries) {
            if (!data) continue;
            const dataURL = data.dataURL || (typeof data.data === 'string' && data.data.startsWith('data:') ? data.data : null);
            const url = data.url || (typeof data.data === 'string' && data.data.startsWith('http') ? data.data : null);

            if (dataURL) {
                toAdd.push({ id, dataURL, mimeType: data.mimeType || 'image/png', created: data.created || Date.now() });
            } else if (url) {
                toFetch.push({ fileId: id, url, mimeType: data.mimeType || 'image/png' });
            }
        }

        if (toAdd.length > 0 && typeof api.addFiles === 'function') {
            api.addFiles(toAdd);
            console.log('[PonyNotes] ✅ Added ' + toAdd.length + ' dataURL files');
            // 回传给 Flutter 补全 dataURL
            _syncFilesToFlutter(filesMap, toAdd);
        }

        if (toFetch.length > 0) {
            console.log('[PonyNotes] 📸 Fetching ' + toFetch.length + ' cloud files...');
            try {
                const results = await window.flutter_inappwebview.callHandler('downloadCloudImages', toFetch);
                if (results && Array.isArray(results) && results.length > 0) {
                    const downloaded = results.map(r => ({
                        id: r.fileId,
                        dataURL: r.dataURL,
                        mimeType: r.mimeType || 'image/png',
                        created: r.created || Date.now()
                    }));
                    api.addFiles(downloaded);
                    console.log('[PonyNotes] ✅ Injected ' + downloaded.length + ' downloaded files');
                    _syncFilesToFlutter(filesMap, downloaded);
                }
            } catch (e) {
                console.error('[PonyNotes] ❌ Cloud download failed:', e);
            }
        }
    }

    /**
     * 将文件状态同步回 Flutter，保护 URL 字段
     */
    function _syncFilesToFlutter(baseMap, newItems) {
        try {
            const fullMap = { ...baseMap };
            newItems.forEach(item => {
                if (fullMap[item.id]) {
                    fullMap[item.id] = { ...fullMap[item.id], dataURL: item.dataURL };
                } else {
                    fullMap[item.id] = item;
                }
            });
            const val = JSON.stringify(fullMap);
            scheduleFlutterStorageSync('excalidraw-files', val);
        } catch (e) { }
    }

    /**
     * ✅ 关键接口：Dart 端主动推送到 WebView
     */
    window.pushWhiteboardData = async function (data) {
        if (!data || !data.key) return;
        const api = window._excalidrawAPI;
        if (!api) {
            console.warn('[PonyNotes] 🔔 Push received but API not ready, saving to payload');
            if (!_initPayload) _initPayload = {};
            _initPayload[data.key] = data.value;
            return;
        }

        try {
            if (data.key === 'elements') {
                api.updateScene({ elements: data.value, commitToHistory: false });
            } else if (data.key === 'appState') {
                enforceHostTheme({ appState: data.value });
                const stableAppState = pickStableAppState(data.value);
                if (_forcedHostTheme) {
                    stableAppState.theme = _forcedHostTheme;
                    if (typeof stableAppState.viewBackgroundColor === 'string' &&
                        stableAppState.viewBackgroundColor.toLowerCase() === '#121212') {
                        stableAppState.viewBackgroundColor = '#ffffff';
                    }
                }
                if (Object.keys(stableAppState).length > 0) {
                    api.updateScene({ appState: stableAppState, commitToHistory: false });
                }
            } else if (data.key === 'files') {
                await _injectFiles(api, data.value);
            }
        } catch (e) {
            console.error('[PonyNotes] ❌ Push update failed:', e);
        }
    };

    function _reconcileElements(localElements, remoteChanged) {
        const byId = new Map();
        for (const element of localElements || []) {
            if (element && element.id) {
                byId.set(element.id, element);
            }
        }

        for (const change of remoteChanged || []) {
            if (!change || !change.id) continue;

            const remoteElement = change.element;
            const localElement = byId.get(change.id);

            if (!remoteElement) {
                if (localElement) {
                    byId.set(change.id, { ...localElement, isDeleted: true });
                }
                continue;
            }

            if (!localElement) {
                byId.set(change.id, remoteElement);
                continue;
            }

            const localVersion = localElement.version || 0;
            const remoteVersion = remoteElement.version || 0;
            if (remoteVersion > localVersion) {
                byId.set(change.id, remoteElement);
            } else if (
                remoteVersion === localVersion &&
                (remoteElement.versionNonce || 0) > (localElement.versionNonce || 0)
            ) {
                byId.set(change.id, remoteElement);
            }
        }

        return Array.from(byId.values());
    }

    window.pushWhiteboardElements = async function (remoteChanged) {
        const api = window._excalidrawAPI;
        if (!api) {
            console.warn('[PonyNotes] 🔔 Element push received but API not ready, saving to payload');
            if (!_initPayload) _initPayload = {};
            _initPayload._pendingElements = (_initPayload._pendingElements || []).concat(remoteChanged || []);
            return;
        }

        try {
            const current = (
                typeof api.getSceneElementsIncludingDeleted === 'function'
                    ? api.getSceneElementsIncludingDeleted()
                    : api.getSceneElements()
            ) || [];
            const merged = _reconcileElements(current.slice(), remoteChanged || []);
            api.updateScene({ elements: merged, commitToHistory: false });
        } catch (e) {
            console.error('[PonyNotes] ❌ pushWhiteboardElements failed:', e);
        }
    };
})();
