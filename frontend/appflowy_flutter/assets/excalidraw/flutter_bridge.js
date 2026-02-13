// ========================================================================
// flutter 桥接功能
// 这个文件将以阻塞行为模式，第一个执行。这时画板的任何代码还未初始化
// ========================================================================
// 功能列表：
//  - localStorage hook，根据viewId隔离，并且同步到后端
// ========================================================================
// 目的：让每个白板视图(viewId)使用独立的localStorage命名空间
// 原理：拦截localStorage API，自动添加viewId前缀
// ========================================================================
(async function () {
    console.log('[PonyNotes] 🔐 Initializing localStorage isolation...');

    // 保存原始localStorage的引用
    const originalLocalStorage = window.localStorage;

    let init = false;

    // ✅ 关键修复：保存 initData 返回的权威数据，避免竞态条件
    // 原因：Excalidraw 的脚本可能在 initData 完成之前就读取 localStorage
    // 如果此时 localStorage 是空的（被 clear() 清掉），Excalidraw 会写入空数据 '[]'
    // 覆盖 initData 后续设置的正确数据。
    // 解决方案：将 initData 返回的数据保存到 JS 变量中，
    // 在 _injectFilesFromStorage 中使用此变量而非 localStorage
    let _initPayload = null;

    // 创建隔离的localStorage代理
    const isolatedStorage = {
        getItem: function (key) {
            const value = originalLocalStorage.getItem(key);
            return value;
        },

        setItem: function (key, value) {
            originalLocalStorage.setItem(key, value);
            if (init) {
                window.flutter_inappwebview.callHandler('localStorageOnSet', {key: key, value});
                
                // 📸 关键修复：当 elements 更新时，自动捕获 files 并同步
                // Excalidraw 不会将 files 写入 localStorage，我们需要手动提取
                if (key.endsWith('excalidraw') && window._excalidrawAPI) {
                    try {
                        // ✅ 改进：使用更可靠的 API 获取 files
                        const api = window._excalidrawAPI;
                        let files = null;
                        
                        // 尝试多种方式获取 files
                        if (typeof api.getFiles === 'function') {
                            files = api.getFiles();
                        } else if (typeof api.getSceneElements === 'function') {
                            // 如果 getFiles 不可用，尝试从 elements 中提取
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
                        
                        if (files && Object.keys(files).length > 0) {
                            const filesKey = key + '-files'; // 定义一个虚拟key
                            const filesValue = JSON.stringify(files);
                            
                            // 简单的防抖/去重，避免重复发送
                            if (window._lastSentFiles !== filesValue) {
                                window._lastSentFiles = filesValue;
                                window.flutter_inappwebview.callHandler('localStorageOnSet', {
                                    key: filesKey, 
                                    value: filesValue
                                });
                                console.log('[PonyNotes] 📸 Synced files count:', Object.keys(files).length);
                            }
                        }
                    } catch (e) {
                         console.error('[PonyNotes] Failed to sync files:', e);
                    }
                }
            }
        },

        removeItem: function (key) {
            originalLocalStorage.removeItem(key);
            if (init) {
                window.flutter_inappwebview.callHandler('localStorageOnRemove', {key: key});
            }
        },

        clear: function () {
            originalLocalStorage.clear();
            if (init) {
                window.flutter_inappwebview.callHandler('localStorageOnClear');
            }
        },

        key: function (index) {
            return originalLocalStorage.key(index);
        },

        // ✅ 修复：返回正确的 length 值
        get length() {
            return originalLocalStorage.length;
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
        console.log('[PonyNotes] ✅ localStorage isolation installed successfully!');
    } catch (e) {
        console.error('[PonyNotes] ❌ Failed to install localStorage isolation:', e);
    }

    originalLocalStorage.clear();

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
            const api = window.excalidrawAPI || window.__EXCALIDRAW_API__ || window._excalidrawAPI;
            if (api) {
                window._excalidrawAPI = api;
                console.log('[PonyNotes] ✅ Excalidraw API captured, restoring data...');
                
                if (!_filesInjected) {
                    _filesInjected = true;
                    try {
                        await _restoreWhiteboardData(api);
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
                    window._excalidrawAPI;
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
    window.loadExcalidrawData = async function (data) {
        try {
            const api = await waitForExcalidrawAPI();
            api.updateScene?.(data || {});
        } catch (e) {
            console.error('[PonyNotes] loadExcalidrawData failed', e);
        }
    };

    // ✅ 关键修复：白板数据恢复函数
    // 使用 _initPayload（从 initData 返回的权威数据）而非 localStorage
    // 这彻底解决了竞态条件：Excalidraw 可能在 initData 完成前就读取 localStorage 并写入空数据
    async function _restoreWhiteboardData(api) {
        try {
            console.log('[PonyNotes] 🔄 Starting whiteboard data restoration...');
            
            // ============================================================
            // 📝 步骤 1：恢复 elements
            // ✅ 关键改进：使用 _initPayload 中的权威数据，而非 localStorage
            // 原因：Excalidraw 可能已经将空数据写入 localStorage，覆盖了 initData 设置的值
            // ============================================================
            let elementsToRestore = null;
            
            // 优先使用 _initPayload 中的数据（最可靠，不受竞态条件影响）
            if (_initPayload) {
                // _initPayload 的 elements 可能是数组或 JSON 字符串
                if (_initPayload.elements) {
                    if (typeof _initPayload.elements === 'string') {
                        try {
                            elementsToRestore = JSON.parse(_initPayload.elements);
                        } catch (e) {
                            console.error('[PonyNotes] ❌ Failed to parse elements from payload:', e);
                        }
                    } else if (Array.isArray(_initPayload.elements)) {
                        elementsToRestore = _initPayload.elements;
                    }
                }
                // 也检查 excalidraw 键（保持向后兼容）
                if (!elementsToRestore && _initPayload.excalidraw) {
                    if (typeof _initPayload.excalidraw === 'string') {
                        try {
                            elementsToRestore = JSON.parse(_initPayload.excalidraw);
                        } catch (e) {
                            console.error('[PonyNotes] ❌ Failed to parse excalidraw from payload:', e);
                        }
                    } else if (Array.isArray(_initPayload.excalidraw)) {
                        elementsToRestore = _initPayload.excalidraw;
                    }
                }
            }
            
            // 回退：从 localStorage 读取（仅当 _initPayload 不可用时）
            if (!elementsToRestore || !Array.isArray(elementsToRestore) || elementsToRestore.length === 0) {
                const elementsStr = originalLocalStorage.getItem('excalidraw');
                if (elementsStr && elementsStr !== '[]' && elementsStr !== 'null') {
                    try {
                        elementsToRestore = JSON.parse(elementsStr);
                    } catch (e) {
                        console.error('[PonyNotes] ❌ Failed to parse elements from localStorage:', e);
                    }
                }
            }
            
            // 恢复 elements
            if (elementsToRestore && Array.isArray(elementsToRestore) && elementsToRestore.length > 0) {
                const currentElements = api.getSceneElements ? api.getSceneElements() : [];
                console.log('[PonyNotes] 📝 Current elements:', currentElements.length, 
                    'Payload elements:', elementsToRestore.length);
                
                // ✅ 关键改进：总是使用权威数据恢复
                // 即使 Excalidraw 当前有元素，也用 _initPayload 中的数据覆盖
                // 因为 Excalidraw 可能读取了不完整或过时的 localStorage 数据
                if (currentElements.length === 0 || 
                    (currentElements.length !== elementsToRestore.length && _initPayload)) {
                    console.log('[PonyNotes] 📝 Restoring', elementsToRestore.length, 'elements via API...');
                    api.updateScene({ elements: elementsToRestore });
                    console.log('[PonyNotes] ✅ Elements restored successfully');
                } else {
                    console.log('[PonyNotes] 📝 Elements already loaded correctly (' + currentElements.length + ')');
                }
            } else {
                console.log('[PonyNotes] 📝 No elements to restore (empty whiteboard)');
            }

            // ============================================================
            // 📸 步骤 2：恢复图片文件
            // ============================================================
            let filesMap = null;
            
            // 优先从 _initPayload 获取 files
            if (_initPayload && _initPayload.files) {
                if (typeof _initPayload.files === 'string') {
                    try {
                        filesMap = JSON.parse(_initPayload.files);
                    } catch (e) {
                        console.error('[PonyNotes] ❌ Failed to parse files from payload:', e);
                    }
                } else if (typeof _initPayload.files === 'object') {
                    filesMap = _initPayload.files;
                }
            }
            
            // 回退：从 localStorage 读取
            if (!filesMap) {
                const filesStr = originalLocalStorage.getItem('excalidraw-files');
                if (filesStr && filesStr !== '{}' && filesStr !== 'null') {
                    try {
                        filesMap = JSON.parse(filesStr);
                    } catch (e) {
                        console.error('[PonyNotes] ❌ Failed to parse files from localStorage:', e);
                    }
                }
            }
            
            if (!filesMap || typeof filesMap !== 'object') {
                console.log('[PonyNotes] 📸 No files to inject');
                return;
            }
            
            const fileEntries = Object.entries(filesMap);
            if (fileEntries.length === 0) {
                console.log('[PonyNotes] 📸 Files map is empty');
                return;
            }
            
            console.log('[PonyNotes] 📸 Found ' + fileEntries.length + ' files to inject');
            
            const filesToAdd = [];
            const cloudFilesToFetch = [];
            
            for (const [fileId, fileData] of fileEntries) {
                if (!fileData || typeof fileData !== 'object') {
                    console.warn('[PonyNotes] ⚠️ Invalid file data for:', fileId);
                    continue;
                }
                
                let dataURL = null;
                
                // 优先使用 base64 dataURL（最可靠）
                if (fileData.dataURL && typeof fileData.dataURL === 'string' && fileData.dataURL.startsWith('data:')) {
                    dataURL = fileData.dataURL;
                } else if (fileData.data && typeof fileData.data === 'string' && fileData.data.startsWith('data:')) {
                    dataURL = fileData.data;
                }
                
                if (dataURL) {
                    filesToAdd.push({
                        id: fileId,
                        dataURL: dataURL,
                        mimeType: fileData.mimeType || 'image/png',
                        created: fileData.created || Date.now(),
                    });
                } else if (fileData.url && typeof fileData.url === 'string' && fileData.url.startsWith('http')) {
                    cloudFilesToFetch.push({ fileId, fileData });
                    console.log('[PonyNotes] 📸 File ' + fileId + ' has cloud URL, will request download from Flutter');
                } else if (fileData.data && typeof fileData.data === 'string' && fileData.data.startsWith('http')) {
                    cloudFilesToFetch.push({ fileId, fileData: { ...fileData, url: fileData.data } });
                    console.log('[PonyNotes] 📸 File ' + fileId + ' has cloud URL in data field');
                } else {
                    console.warn('[PonyNotes] ⚠️ No valid dataURL or cloud URL for file:', fileId, 
                        'keys:', Object.keys(fileData));
                }
            }
            
            // 注入已有 dataURL 的文件
            if (filesToAdd.length > 0) {
                console.log('[PonyNotes] 📸 Injecting ' + filesToAdd.length + ' files with dataURL...');
                if (typeof api.addFiles === 'function') {
                    api.addFiles(filesToAdd);
                    console.log('[PonyNotes] ✅ Injected ' + filesToAdd.length + ' files via addFiles()');
                } else {
                    console.warn('[PonyNotes] ⚠️ addFiles not available');
                }
            }
            
            // 对于需要从云端下载的文件，通知 Flutter 下载
            if (cloudFilesToFetch.length > 0) {
                console.log('[PonyNotes] 📸 Requesting Flutter to download ' + cloudFilesToFetch.length + ' cloud images...');
                try {
                    const cloudFileIds = cloudFilesToFetch.map(f => ({
                        fileId: f.fileId,
                        url: f.fileData.url,
                        mimeType: f.fileData.mimeType || 'image/png',
                    }));
                    const result = await window.flutter_inappwebview.callHandler('downloadCloudImages', cloudFileIds);
                    if (result && Array.isArray(result)) {
                        const downloadedFiles = [];
                        for (const item of result) {
                            if (item && item.fileId && item.dataURL) {
                                downloadedFiles.push({
                                    id: item.fileId,
                                    dataURL: item.dataURL,
                                    mimeType: item.mimeType || 'image/png',
                                    created: item.created || Date.now(),
                                });
                            }
                        }
                        if (downloadedFiles.length > 0 && typeof api.addFiles === 'function') {
                            api.addFiles(downloadedFiles);
                            console.log('[PonyNotes] ✅ Injected ' + downloadedFiles.length + ' downloaded cloud images');
                        }
                    }
                } catch (e) {
                    console.error('[PonyNotes] ❌ Failed to download cloud images:', e);
                }
            }
            
            console.log('[PonyNotes] 📸 File injection complete. Total: ' + filesToAdd.length + ' local + ' + cloudFilesToFetch.length + ' cloud');
        } catch (e) {
            console.error('[PonyNotes] ❌ Failed to restore whiteboard data:', e);
        }
    }
})();
