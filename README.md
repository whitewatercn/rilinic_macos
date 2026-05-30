由　[中州韻輸入法引擎／Rime Input Method Engine](https://rime.im)
基于 [squirrel](https://github.com/rime/squirrel) 二次开发

# 如何打包 pkg
---

本項目通過 `Makefile` 生成 macOS 安裝包，輸出文件爲 `package/rilinic.pkg`。

### 1. 準備依賴

首次打包前，先拉取或生成 librime、Sparkle 等依賴。一般使用預編譯依賴最快：

```bash
./action-install.sh
```

如果需要從源碼編譯依賴：

```bash
make deps
```

### 2. 生成本地測試 pkg

```bash
make clean-package
make package
```

這會先構建 Release 版 `rilinic.app`，再調用 `package/make_package` 使用 `pkgbuild` 打包。
生成結果：

```text
package/rilinic.pkg
```

本地安裝測試：

```bash
sudo installer -pkg package/rilinic.pkg -target /
```

安裝位置是：

```text
/Library/Input Methods/rilinic.app
```

### 3. 生成正式簽名與公證 pkg

正式分發時需要 Developer ID。`DEV_ID` 應與鑰匙串中的簽名身份及 `notarytool` profile 名稱一致：

```bash
make clean-package
make package DEV_ID="Your Developer ID"
```

該流程會依次執行：

1. 構建 Release 版 `rilinic.app`
2. 使用 `Developer ID Application` 簽名 `.app`
3. 使用 `pkgbuild` 生成 `package/rilinic.pkg`
4. 使用 `Developer ID Installer` 簽名 `.pkg`
5. 使用 `xcrun notarytool submit` 提交公證
6. 使用 `xcrun stapler staple` 裝訂公證票據

如需生成帶版本號的發布包和 Sparkle appcast：

```bash
make archive DEV_ID="Your Developer ID"
```

發布歸檔會在 `package/` 下生成類似 `rilinic-<版本號>.pkg` 的文件。

使用輸入法
---

選取輸入法指示器菜單裏的【ㄓ】字樣圖標，開始用鼠鬚管寫字。
通過快捷鍵 `` Ctrl+` `` 或 `F4` 呼出方案選單、切換輸入方式。

定製輸入法
---

定製方法，請參考線上 [幫助文檔](https://rime.im/docs/)。

使用系統輸入法菜單：

  * 選中「在線文檔」可打開以上網址
  * 編輯用戶設定後，選擇「重新部署」以令修改生效

配置管理
---

使用輸入法菜單中的「医键通」入口登录并获取云端词库、配置文件更新。

致謝
---

輸入方案設計：

  * 【朙月拼音】系列

    感謝 CC-CEDICT、Android 拼音、新酷音、opencc 等開源項目

程序設計：

  * 佛振
  * Linghua Zhang
  * Chongyu Zhu
  * 雪齋
  * faberii
  * Chun-wei Kuo
  * Junlu Cheng
  * Jak Wings
  * xiehuc

美術：

  * 圖標設計 佛振、梁海、雨過之後
  * 配色方案 Aben、Chongyu Zhu、skoj、Superoutman、佛振、梁海

本品引用了以下開源軟件：

  * Boost C++ Libraries  (Boost Software License)
  * capnproto (MIT License)
  * darts-clone  (New BSD License)
  * google-glog  (New BSD License)
  * Google Test  (New BSD License)
  * LevelDB  (New BSD License)
  * librime  (New BSD License)
  * OpenCC / 開放中文轉換  (Apache License 2.0)
  * Sparkle  (MIT License)
  * UTF8-CPP  (Boost Software License)
  * yaml-cpp  (MIT License)

感謝王公子捐贈開發用機。

問題與反饋
---

發現程序有 BUG，或建議，或感想，請反饋到 [Rime 代碼之家討論區](https://github.com/rime/home/discussions)

聯繫方式
---

技術交流，歡迎光臨 [Rime 代碼之家](https://github.com/rime/home)，
或致信 Rime 開發者 <rimeime@gmail.com>。

謝謝
