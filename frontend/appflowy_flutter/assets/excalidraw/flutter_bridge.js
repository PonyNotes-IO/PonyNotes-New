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
            console.log(`[PonyNotes Storage] getItem("${key}") -> prefixed: "${key}" -> ${value ? 'HAS_DATA' : 'null'}`);
            return value;
        },

        setItem: function (key, value) {
            originalLocalStorage.setItem(key, value);
            if (init) {
                window.flutter_inappwebview.callHandler('localStorageOnSet', {key: key, value});
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

        // ✅ 修复：返回正确的 length 值，而不是每次都清空数据
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
        // console.log('[PonyNotes] 🔐 All localStorage operations will be scoped to viewId:', currentViewId);
    } catch (e) {
        console.error('[PonyNotes] ❌ Failed to install localStorage isolation:', e);
    }

    originalLocalStorage.clear();
    await window.flutter_inappwebview.callHandler('initData');
    init = true;

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
})();