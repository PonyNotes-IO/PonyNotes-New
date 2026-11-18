/*
 * Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import web_webview from '@ohos.web.webview';
import router from '@ohos.router';
import { ValueType } from '@kit.ArkData';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { emitter } from '@kit.BasicServicesKit';
import window from '@ohos.window';
import common from '@ohos.app.ability.common';

@Entry
@Component
export struct InAppBrowser {
  webviewController: web_webview.WebviewController = new web_webview.WebviewController()

  private url?: string;
  private enableJavaScript: boolean = true;
  private enableDomStorage: boolean = true;
  @State statusBarHeight: number = 32;

  aboutToDisappear() {
    emitter.off("closeWebView");
  }

  aboutToAppear(){
    let params = router.getParams() as Map<string, ValueType>
    this.url = params['url'] as string;
    let options = params['options'] as Map<string, ValueType>;
    this.enableJavaScript = options['enableJavaScript'] as boolean;
    this.enableDomStorage = options['enableDomStorage'] as boolean;
    emitter.once("closeWebView", () => {
      router.back();
      Log.d("InAppBrowser", "closeWebView done");
   });
    try {
      let context = getContext(this) as common.UIAbilityContext;
      window.getLastWindow(context).then((win) => {
        let avoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        let height = px2vp(avoidArea.topRect.height);
        if (height > 0) {
          this.statusBarHeight = height;
        }
      }).catch((e: Error) => {
        console.error('InAppBrowser: Failed to get status bar height: ' + JSON.stringify(e));
      });
    } catch (e) {
      console.error('InAppBrowser: Failed to get context: ' + JSON.stringify(e));
    }
  }

  build() {
    Row() {
      Web({ src: this.url, controller: this.webviewController })
        .javaScriptAccess(this.enableJavaScript)
        .domStorageAccess(this.enableDomStorage)
    }.width('100%').height('100%')
     .padding({ top: this.statusBarHeight })
  }
}
