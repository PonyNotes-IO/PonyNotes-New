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

        get length() {
            originalLocalStorage.clear();
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
})();