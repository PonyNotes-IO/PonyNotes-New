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
    // /**
    //  * 解析 URL 中的所有参数（支持 query 和 path 中 viewId=xxx 形式）
    //  * @param {string} urlStr
    //  * @returns {Record<string, string>} 参数对象
    //  */
    // function parseUrlParams(urlStr = window.location.href) {
    //     const params = {};
    //
    //     try {
    //         const url = new URL(urlStr);
    //
    //         // 1️⃣ 先解析 query 参数
    //         for (const [key, value] of url.searchParams.entries()) {
    //             params[key] = value;
    //         }
    //
    //         // 2️⃣ 再解析路径中可能存在的 key=value 形式
    //         const pathParts = url.pathname.split('/');
    //         for (const part of pathParts) {
    //             const match = part.match(/^([^=]+)=(.+)$/);
    //             if (match) {
    //                 const [, key, value] = match;
    //                 if (!(key in params)) { // query 优先
    //                     params[key] = value;
    //                 }
    //             }
    //         }
    //     } catch (e) {
    //         console.error('[PonyNotes] Failed to parse URL params:', e);
    //     }
    //
    //     return params;
    // }
    //
    // // 从URL路径提取viewId（格式：http://127.0.0.1:xxxx/whiteboard/index.html/viewId={viewId}）
    // const allParams = parseUrlParams();
    // let currentViewId = allParams.viewId || null;
    console.log('[PonyNotes] 🔐 Initializing localStorage isolation...');
    // console.log('[PonyNotes] 🆔 Current viewId:', currentViewId || 'unknown');

    // 保存原始localStorage的引用
    const originalLocalStorage = window.localStorage;

    // originalLocalStorage.setItem('whiteboard_2f6baa3b-f8e7-4551-b553-1b7f3802d299_excalidraw', '[{"id":"9PhCCR1kTVFHVnPs3Mp3K","type":"rectangle","x":393,"y":203,"width":351,"height":184,"angle":0,"strokeColor":"#1e1e1e","backgroundColor":"transparent","fillStyle":"solid","strokeWidth":2,"strokeStyle":"solid","roughness":1,"opacity":100,"groupIds":[],"frameId":null,"index":"a0","roundness":{"type":3},"seed":872014341,"version":10,"versionNonce":311623397,"isDeleted":false,"boundElements":null,"updated":1762427879424,"link":null,"locked":false},{"id":"m0kkeUsoOo1g8aoe3hQ0P","type":"ellipse","x":342,"y":227,"width":270,"height":252,"angle":0,"strokeColor":"#1e1e1e","backgroundColor":"transparent","fillStyle":"solid","strokeWidth":2,"strokeStyle":"solid","roughness":1,"opacity":100,"groupIds":[],"frameId":null,"index":"a1","roundness":{"type":2},"seed":1475104555,"version":7,"versionNonce":756141861,"isDeleted":false,"boundElements":null,"updated":1762427880512,"link":null,"locked":false},{"id":"YoZXd6k_fyrndPlsTm_ll","type":"arrow","x":707,"y":110,"width":128,"height":505,"angle":0,"strokeColor":"#1e1e1e","backgroundColor":"transparent","fillStyle":"solid","strokeWidth":2,"strokeStyle":"solid","roughness":1,"opacity":100,"groupIds":[],"frameId":null,"index":"a2","roundness":{"type":2},"seed":1337963243,"version":10,"versionNonce":937132043,"isDeleted":false,"boundElements":null,"updated":1762427881443,"link":null,"locked":false,"points":[[0,0],[128,505]],"lastCommittedPoint":null,"startBinding":null,"endBinding":null,"startArrowhead":null,"endArrowhead":"arrow","elbowed":false},{"id":"IeuLjFCt3h2unVKd90dI2","type":"line","x":674,"y":170,"width":123,"height":248,"angle":0,"strokeColor":"#1e1e1e","backgroundColor":"transparent","fillStyle":"solid","strokeWidth":2,"strokeStyle":"solid","roughness":1,"opacity":100,"groupIds":[],"frameId":null,"index":"a3","roundness":{"type":2},"seed":2063456235,"version":8,"versionNonce":968428139,"isDeleted":false,"boundElements":null,"updated":1762427882681,"link":null,"locked":false,"points":[[0,0],[-123,248]],"lastCommittedPoint":null,"startBinding":null,"endBinding":null,"startArrowhead":null,"endArrowhead":null,"polygon":false}]');
    // originalLocalStorage.setItem('whiteboard_2f6baa3b-f8e7-4551-b553-1b7f3802d299_excalidraw-state', '{"showWelcomeScreen":true,"theme":"light","currentChartType":"bar","currentItemBackgroundColor":"transparent","currentItemEndArrowhead":"arrow","currentItemFillStyle":"solid","currentItemFontFamily":5,"currentItemFontSize":20,"currentItemOpacity":100,"currentItemRoughness":1,"currentItemStartArrowhead":null,"currentItemStrokeColor":"#1e1e1e","currentItemRoundness":"round","currentItemArrowType":"round","currentItemStrokeStyle":"solid","currentItemStrokeWidth":2,"currentItemTextAlign":"left","cursorButton":"up","editingGroupId":null,"activeTool":{"type":"selection","customType":null,"locked":false,"fromSelection":false,"lastActiveTool":null},"penMode":false,"penDetected":false,"exportBackground":true,"exportScale":1,"exportEmbedScene":false,"exportWithDarkMode":false,"gridSize":20,"gridStep":5,"gridModeEnabled":false,"defaultSidebarDockedPreference":false,"lastPointerDownWith":"mouse","name":"Untitled-2025-11-06-1917","openMenu":null,"openSidebar":null,"previousSelectedElementIds":{},"scrolledOutside":false,"scrollX":0,"scrollY":0,"selectedElementIds":{"IeuLjFCt3h2unVKd90dI2":true},"selectedGroupIds":{},"shouldCacheIgnoreZoom":false,"stats":{"open":false,"panels":3},"viewBackgroundColor":"#ffffff","zenModeEnabled":false,"zoom":{"value":1},"selectedLinearElement":{"elementId":"IeuLjFCt3h2unVKd90dI2","selectedPointsIndices":null,"pointerDownState":{"prevSelectedPointsIndices":null,"lastClickedPoint":-1,"lastClickedIsEndPoint":false,"origin":null,"segmentMidpoint":{"value":null,"index":null,"added":false}},"isDragging":false,"lastUncommittedPoint":null,"pointerOffset":{"x":0,"y":0},"startBindingElement":"keep","endBindingElement":"keep","hoverPointIndex":-1,"segmentMidPointHoveredCoords":null,"elbowed":false,"customLineAngle":null,"isEditing":false},"objectsSnapModeEnabled":false,"lockedMultiSelections":{},"stylesPanelMode":"full"}');
    // originalLocalStorage.setItem('whiteboard_2f6baa3b-f8e7-4551-b553-1b7f3802d299_excalidraw-theme', 'light');
    // originalLocalStorage.setItem('whiteboard_2f6baa3b-f8e7-4551-b553-1b7f3802d299_i18nextLng', 'zh-CN');
    // originalLocalStorage.setItem('whiteboard_2f6baa3b-f8e7-4551-b553-1b7f3802d299_version-dataState', '1762427884038');
    // originalLocalStorage.setItem('whiteboard_2f6baa3b-f8e7-4551-b553-1b7f3802d299_version-files', '1762427884038');

    let init = false;

    // 创建隔离的localStorage代理
    const isolatedStorage = {
        getItem: function (key) {
            const value = originalLocalStorage.getItem(key);
            // console.log(`[PonyNotes Storage] getItem("${key}") -> prefixed: "${key}" -> ${value ? 'HAS_DATA' : 'null'}`);
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
                window.flutter_inappwebview.callHandler('localStorageOnRemove', {key: key, value});
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
    await window.flutter_inappwebview.callHandler('initData');
    init = true;
    
    // 初始化完成后，尝试获取API引用并注入文件（作为安全网）
    // ✅ 关键：如果 _onWhiteboardDataReady 由于时序问题未被调用，
    // 这个轮询机制将作为备用方案注入文件
    let _filesInjected = false; // 标记文件是否已注入，避免重复注入
    
    setTimeout(() => {
        let attempts = 0;
        const interval = setInterval(async () => {
            const api = window.excalidrawAPI || window.__EXCALIDRAW_API__ || window._excalidrawAPI;
            if (api) {
                window._excalidrawAPI = api;
                console.log('[PonyNotes] ✅ Excalidraw API captured for storage hooks');
                clearInterval(interval);
                
                // ✅ 安全网：如果 _onWhiteboardDataReady 尚未注入文件，在这里注入
                if (!_filesInjected) {
                    _filesInjected = true;
                    console.log('[PonyNotes] 📸 Safety net: injecting files from polling mechanism...');
                    try {
                        await _injectFilesFromStorage(api);
                    } catch (e) {
                        console.error('[PonyNotes] ❌ Safety net file injection failed:', e);
                    }
                }
            }
            attempts++;
            if (attempts > 50) clearInterval(interval);
        }, 200);
    }, 1000);

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
                        // 如果返回的是Blob，读取为文本
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

    // ✅ 关键修复：白板数据加载完成回调 - 注入图片文件到 Excalidraw
    // 原因：Excalidraw 将图片存储在内部 React 状态和 IndexedDB 中，而不是 localStorage
    // 因此我们必须使用 api.addFiles() 将图片数据直接注入到 Excalidraw 中
    window._onWhiteboardDataReady = async function (count) {
        console.log('[PonyNotes] ✅ Whiteboard data ready, ' + count + ' items loaded');
        try {
            const api = await waitForExcalidrawAPI();
            window._excalidrawAPI = api;
            console.log('[PonyNotes] ✅ Excalidraw API ready, injecting files...');
            
            // 📸 关键修复：从 localStorage 读取 files 并注入到 Excalidraw
            if (!_filesInjected) {
                _filesInjected = true;
                await _injectFilesFromStorage(api);
            } else {
                console.log('[PonyNotes] 📸 Files already injected by safety net, skipping');
            }
            
            console.log('[PonyNotes] ✅ Whiteboard initialization complete');
        } catch (e) {
            console.error('[PonyNotes] Failed to initialize whiteboard:', e);
        }
    };

    // 📸 恢复白板完整数据：先确保 elements 正确，再注入 files
    async function _injectFilesFromStorage(api) {
        try {
            // ============================================================
            // 🔒 步骤 1：确保 elements 已正确加载（防止竞态条件导致丢失）
            // 原因：initData 是异步的，如果 Excalidraw 在 localStorage 
            //       设置之前就读取了数据，elements 会为空
            // ============================================================
            const currentElements = api.getSceneElements ? api.getSceneElements() : [];
            console.log('[PonyNotes] 📝 Current elements count:', currentElements.length);
            
            if (currentElements.length === 0) {
                // Excalidraw 当前没有 elements，尝试从 localStorage 恢复
                const elementsStr = originalLocalStorage.getItem('excalidraw');
                if (elementsStr && elementsStr !== '[]' && elementsStr !== 'null') {
                    try {
                        const elements = JSON.parse(elementsStr);
                        if (Array.isArray(elements) && elements.length > 0) {
                            console.log('[PonyNotes] 📝 Restoring ' + elements.length + ' elements via API...');
                            api.updateScene({ elements: elements });
                            console.log('[PonyNotes] ✅ Elements restored successfully');
                        }
                    } catch (e) {
                        console.error('[PonyNotes] ❌ Failed to parse/restore elements:', e);
                    }
                }
            } else {
                console.log('[PonyNotes] 📝 Elements already loaded (' + currentElements.length + '), no restore needed');
            }

            // ============================================================
            // 📸 步骤 2：注入图片文件
            // ============================================================
            const filesStr = originalLocalStorage.getItem('excalidraw-files');
            if (!filesStr || filesStr === '{}' || filesStr === 'null') {
                console.log('[PonyNotes] 📸 No files to inject');
                return;
            }
            
            let filesMap;
            try {
                filesMap = JSON.parse(filesStr);
            } catch (e) {
                console.error('[PonyNotes] ❌ Failed to parse files JSON:', e);
                return;
            }
            
            if (!filesMap || typeof filesMap !== 'object') {
                console.log('[PonyNotes] 📸 No valid files data');
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
            console.error('[PonyNotes] ❌ Failed to inject files:', e);
        }
    }
})();