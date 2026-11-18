// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.

import { InAppBrowser } from 'url_launcher_ohos/src/main/ets/components/plugin/InAppBrowser';

@Entry
@Component
struct LaunchInAppPage {

  build() {
    Row() {
      InAppBrowser()
    }
  }
}
