import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../presentation/webview_async_eval.dart';

/// Registered by the live editor; edits use the same Excalidraw API and save
/// path as human actions instead of overwriting an independent scene snapshot.
class WhiteboardToolBridge {
  static final _editors = <String, InAppWebViewController>{};
  static final _flushers = <String, Future<void> Function()>{};
  static void register(
    String view,
    InAppWebViewController controller, {
    Future<void> Function()? flush,
  }) {
    _editors[view] = controller;
    if (flush != null) _flushers[view] = flush;
  }

  static void unregister(String view, InAppWebViewController? controller) {
    if (_editors[view] == controller) {
      _editors.remove(view);
      _flushers.remove(view);
    }
  }

  static bool isOpen(String view) => _editors.containsKey(view);

  static Future<Map<String, dynamic>> execute(
    String view,
    Map<String, dynamic> request,
  ) async {
    final controller = _editors[view];
    if (controller == null) throw StateError('请先打开白板以使用实时编辑与导出');
    final result = await evaluateAsyncJavascript(
      controller,
      asyncBody: '''
const request = ${jsonEncode(request)};
const api = (typeof window.__xmGetExcalidrawAPI === 'function' && window.__xmGetExcalidrawAPI()) || window.excalidrawAPI || window._excalidrawAPI || window.__EXCALIDRAW_API__;
if (!api || typeof api.getSceneElements !== 'function') return {error:'编辑器尚未就绪'};
let elements = api.getSceneElements();
if (request.action === 'capabilities') return {open:true,save_available:typeof window.__xmForceSave==='function' || ${_flushers.containsKey(view)},formats:['ponynotes',...(window.exportToSvg || window.ExcalidrawLib?.exportToSvg ? ['svg'] : []),...(window.exportToBlob || window.ExcalidrawLib?.exportToBlob ? ['png'] : [])]};
if (['save','edit','import'].includes(request.action) && typeof window.__xmForceSave!=='function' && !${_flushers.containsKey(view)}) return {error:'当前编辑器未连接可确认的保存路径'};
if (request.action === 'read') return {elements, appState:api.getAppState(), files:api.getFiles ? api.getFiles() : {}};
if (request.action === 'save') {
  if (typeof window.__xmForceSave === 'function') await window.__xmForceSave('mcp');
  return {saved:true};
}
if (request.action === 'export') {
  const exported = {type:'excalidraw',version:2,elements,appState:api.getAppState(),files:api.getFiles ? api.getFiles() : {}};
  if (request.format === 'svg') {
    const exporter=window.exportToSvg || window.ExcalidrawLib?.exportToSvg;
    if(!exporter) return {error:'当前编辑器未提供SVG导出'};
    const svg=await exporter(exported);return {text:svg.outerHTML};
  }
  if (request.format === 'png') {
    const exporter=window.exportToBlob || window.ExcalidrawLib?.exportToBlob;
    if(!exporter) return {error:'当前编辑器未提供PNG导出'};
    const blob=await exporter({...exported,mimeType:'image/png'});
    const data=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=reject;reader.readAsDataURL(blob);});
    return {base64:data.split(',')[1]};
  }
  return {json:JSON.stringify(exported)};
}
if(request.action === 'import') {
  const incoming=request.scene;
  if(!incoming || !Array.isArray(incoming.elements))return {error:'场景格式无效'};
  const ids=new Set(elements.map(e=>e.id));
  for(const element of incoming.elements) {if(!element.id || ids.has(element.id))return {error:'导入元素ID冲突；请先调整场景ID再合并'};ids.add(element.id);}
  if(incoming.files && api.addFiles)api.addFiles(Object.values(incoming.files));
  api.updateScene({elements:[...elements,...incoming.elements],commitToHistory:true});
  if(typeof window.__xmForceSave === 'function')await window.__xmForceSave('mcp-import');
  return {imported:incoming.elements.length};
}
if (request.action === 'edit') {
  const operations = request.operations || [];
  for (const operation of operations) {
    if(operation.action==='reorder') {
      const ids=operation.element_ids;
      if(!Array.isArray(ids) || ids.length!==elements.length || new Set(ids).size!==elements.length || elements.some(e=>!ids.includes(e.id) || operation.expected_versions?.[e.id]!==e.version))return {error:'排序须提供全部元素ID和最新版本'};
      const byId=new Map(elements.map(e=>[e.id,e]));elements=ids.map(id=>byId.get(id));continue;
    }
    const index = elements.findIndex(e => e.id === operation.element_id);
    if (operation.action === 'add') {
      if (!operation.element || !operation.element.id || elements.some(e=>e.id===operation.element.id)) return {error:'新增元素缺少唯一ID'};
      elements = [...elements, operation.element];
    } else {
      if(!['update','delete'].includes(operation.action))return {error:'未知元素操作'};
      if (index < 0) return {error:'元素不存在'};
      const current = elements[index];
      if (operation.expected_version !== current.version) return {error:'元素版本已变化，请重新读取'};
      const patch = operation.action === 'delete' ? {isDeleted:true} : operation.properties;
      if (!patch || patch.id || patch.version || patch.versionNonce) return {error:'不能覆盖元素身份或版本'};
      elements = elements.map((e,i) => i === index ? {...e,...patch,version:e.version+1,versionNonce:Math.floor(Math.random()*2147483647),updated:Date.now()} : e);
    }
  }
  const state=request.view_state || {};
  const appState={...(typeof state.scrollX==='number'?{scrollX:state.scrollX}:{}),...(typeof state.scrollY==='number'?{scrollY:state.scrollY}:{}),...(typeof state.zoom==='number'?{zoom:{value:state.zoom}}:{})};
  api.updateScene({elements,appState,commitToHistory:true});
  if (typeof window.__xmForceSave === 'function') await window.__xmForceSave('mcp-edit');
  return {updated:true,elements:api.getSceneElements()};
}
return {error:'未知白板动作'};
''',
      debugLabel: 'MCP-whiteboard',
    );
    if (result is! Map) throw StateError('白板调用未能确认结果，请重新读取');
    if (result['error'] != null) throw StateError('${result['error']}');
    if (const ['save', 'edit', 'import'].contains(request['action'])) {
      final flush = _flushers[view];
      if (flush != null) await flush();
      result['persistence'] = 'submitted_to_editor_save_path';
    }
    return Map<String, dynamic>.from(result);
  }
}
