---
name: win-upgrade-doctor
description: Windows 10/11 功能更新（大版本升級，例如 23H2→24H2/25H2/26H2、Win10→Win11）的升級前體檢、升級中即時監控、失敗後日誌診斷與升級後收尾。當使用者提到升級失敗、0xC1900101 或任何 0xC19xxxxx / 0x800xxxxx 升級錯誤碼、「卡在 xx% 不動」、「正在處理更新」很久、「正在還原先前的 Windows 版本」、回滾、SetupDiag、setupact.log / setuperr.log / $WINDOWS.~BT / Panther 日誌、用 ISO 的 setup.exe 升級、Windows Update 功能更新一直失敗、想知道升級會不會成功、想遠端讓升級自己跑、或升級完要檢查與還原設定（Windows.old、TEMP、驅動）時，都要使用這個 skill，即使使用者沒說「診斷」兩個字。Use for any Windows feature-update / in-place upgrade problem, pre-flight check, live monitoring, or post-upgrade verification.
---

> 這是 skill 的**繁體中文版**，供閱讀與參考。實際安裝、由 Claude 載入的是 [skills/win-upgrade-doctor/](../../skills/win-upgrade-doctor/SKILL.md)（英文，Claude 會用使用者的語言回答）。文中提到的 `scripts/` 位於該資料夾。

# Windows 升級醫生

協助使用者完成 Windows **功能更新 / 就地升級**（in-place upgrade）：升級前找出地雷、升級中看懂進度、失敗後找出真因、升級後收尾。

這個 skill 的價值在於**少走彎路**。升級日誌又大又吵，充滿看起來像錯誤、其實無害的訊息；錯誤碼又很籠統（0xC1900101 只代表「回滾了」）。沒有方法的話，很容易先入為主（例如直接怪防毒軟體）、或把正常行為誤判成失敗。下面的流程與參考文件都是從真實案例的誤判中整理出來的。

## 先判斷使用者在哪個階段

| 情境 | 去哪一節 |
|---|---|
| 還沒升級、想先檢查，或上次失敗想重試 | [A. 升級前體檢](#a-升級前體檢) |
| 升級正在跑（電腦還在原本的系統裡） | [B. 升級中監控](#b-升級中監控) |
| 已經失敗回滾，或卡住後被強制重開 | [C. 失敗診斷](#c-失敗診斷) |
| 升級成功、回到桌面 | [D. 升級後收尾](#d-升級後收尾) |
| 一般問題：該用 ISO 還是 Windows Update、26H2 要不要重裝、能不能改使用者資料夾名稱…… | 讀 `references/scenarios.md` |

## 安全與同意的規則

升級動的是整台電腦，以下規則保護使用者，不要省略：

- **刪除檔案交給使用者自己執行**。可以給指令、說明刪什麼、為什麼安全，但不要自己刪。刪之前先證明內容是什麼（例如「31,451 個資料夾、0 個檔案、0 MB」）。
- **啟動升級前取得明確同意**：`/eula accept` 等於代替使用者接受授權條款，`/auto upgrade` 會自動重開機。說清楚這兩件事再執行。
- **先說清楚 Claude 的極限**：Claude 跑在使用者的電腦上，**第一次重開機後就斷線**，SafeOS、首次開機、OOBE 這些階段完全看不到，要等使用者回到桌面重新叫醒。不要承諾「重開後我會繼續盯著」。
- **建議不要在「看起來卡住」時強制關機**。強制關機本身就會造成 0xC1900101 回滾；很多「卡住」其實是在慢慢處理（見案例）。
- 修改環境變數、停用服務等設定前先記下原值，方便升級後還原。

## A. 升級前體檢

執行 `scripts/preflight.ps1`（唯讀；只有 `-IsoPath` 會掛載 ISO。需系統管理員權限才看得到完整資訊）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/preflight.ps1" [-IsoPath D:\xxx.iso]
```

它會檢查並用 `[OK] / [WARN] / [FAIL]` 標示：

1. 目前版本、版別、語系、上次升級失敗的殘留（`$WINDOWS.~BT`、`0xC19…` 紀錄）
2. **`C:\Windows\SystemTemp` 的項目數**，特別是 `chrome_url_fetcher_*` / `msedge_url_fetcher_*` 空資料夾。升級時這裡的每個項目都要逐一遷移，實測約 0.5–1 秒一個，**幾萬個就是好幾小時**，看起來像卡在 20–30%
3. 使用者與系統的 TEMP / TMP 是否指向 RAM disk、可移除磁碟或不存在的路徑（SafeOS 裡這些磁碟不存在）
4. 已載入的第三方檔案系統過濾驅動（`fltmc`）與第三方儲存驅動：備份軟體、防毒/EDR、加密、RAM disk、虛擬光碟
5. C: 剩餘空間、待重開機狀態、多顆磁碟上是否有多個系統（EFI）分割區
6. 如果給了 ISO：版別、語系、build 是否與目前系統相符（不符就不能保留檔案與程式）

把結果翻成白話給使用者，每一項附上「影響」和「建議動作」。只有確實有證據的項目才建議處理；**不要因為裝了某套軟體就要求整套移除**——先暫停或停用，等日誌證實它出事再談移除。

## B. 升級中監控

### 啟動升級（使用者同意後）

```powershell
<ISO 掛載槽>:\setup.exe /auto upgrade /quiet /eula accept /dynamicupdate enable
```

- `/dynamicupdate enable` 會先下載最新累積更新再整合（可能數 GB、多花 10–30 分鐘），好處是裝完就是最新版、安裝程式本身也是修正版。網路差或想快一點可用 `disable`。
- 啟動後 1 分鐘內可能看到 `0x800705BB`、`0x800704D3`、`CheckUserInterrupt`——**這通常是安裝程式自我更新後重新啟動**（SetupHost 的 PID 會換掉，對應官方代碼 `0xC1900129 UPDATEMEDIA_REQUESTED`）。先確認 SetupHost 還在、日誌還在長，**不要急著重跑**。

### 監看日誌

用 Monitor 工具執行 `scripts/watch.ps1`（最長 30 分鐘一輪，到期就重新啟動）：

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/watch.ps1"
```

它只輸出值得回報的事件：`STEP`（關鍵步驟開始）、`PROGRESS`（最多每 5 分鐘一次）、`INFO`（例如自我更新重啟）、`REBOOT_SOON`、`FAIL`、`STALE`（日誌 15 分鐘沒動）、`SETUPHOST_GONE`。回報給使用者時要說明「現在在做什麼、正常嗎、接下來是什麼」，一兩句就好。

調整過濾條件後，用 `-Replay -LogPath <舊的 setupact.log>` 拿一份已完成的日誌回放，確認沒有誤報、重開機前兆有抓到，再拿去監看正在進行的升級。

判讀前務必先看 `references/log-guide.md` 的「無害訊息清單」與「階段時間軸」——**`Action progress` 是每個步驟各自 0→100%，會反覆歸零**；`Rollback Enabled`、`Restartable: [no]`、`Reboot required: no`、待辦步驟表等都不是失敗或重開機訊號。

使用者人不在電腦前時，`REBOOT_SOON`（`Executing operation: Orchestrate OS switch`）是唯一可靠的重開機前兆，通常只提前幾十秒到兩分鐘。收到時：簡短總結進度、給出成功機率評估（附信心程度）、提醒重開後不要強制關機，然後讓它自然重開。可以的話用 PushNotification 推播。

## C. 失敗診斷

執行 `scripts/diagnose.ps1`（唯讀）。它會依序：

1. 從 `$WINDOWS.~BT\Sources\Rollback\setupact.log` 找出 `Reporting post reboot event -> [0xC19xxxxx, 0xNNNNN]`——**這一行已經是完整的錯誤碼與延伸碼**，不必先下載 SetupDiag
2. 判斷**有沒有當機**：`Current bugcheck string`、`No crash detected`、`FatalErrorCode`、`setupmem.dmp`
3. 列出 `Current phase string`、主日誌 `setupact.log` **最後在做的事**（最後 N 行裡重複最多的動作）以及它開始重複的時間
4. 搜尋使用者指定的關鍵字（例如懷疑的驅動名稱），區分「只出現在盤點清單」與「出現在 Error/Warning 行」
5. 如果主日誌被清掉，改找 `C:\Windows\Panther`、`C:\Windows.old` 或 `C:\Windows\Logs\SetupDiag\SetupDiagResults.xml`

### 判讀順序（避免先入為主）

1. **先拆延伸碼**：第一位是階段、後兩位是作業（對照 `references/error-codes.md`）
2. **有 bugcheck / dump？** 有 → 驅動或硬體問題，從 dump 或 bugcheck 參數找模組；沒有 → 往下
3. **最後在做什麼？** 如果是大量重複的遷移動作（`Processing File`、`RECAPPLY`），而使用者曾強制重開 → **真因是「太慢被打斷」**，不是驅動。找出被大量處理的路徑
4. **懷疑某軟體時看證據**：名稱只出現在相容性盤點、服務清單 → 不算證據；出現在 Error 行、bugcheck 模組、setupapi.dev.log 的失敗安裝 → 才算
5. 對照 `references/error-codes.md` 的常見原因給建議

### 回報格式

用表格列出：錯誤碼與延伸碼、階段、作業、有無當機、最後的動作、可疑元件。每個結論標上信心程度：

- **確定**：日誌原文直接寫明
- **高度懷疑**：多項證據指向，但需要推論
- **需要進一步驗證**：只有間接跡象或缺資料

最後給**有順序的**下一步（先做成本最低、證據最強的），並說明重試時要觀察什麼。

## D. 升級後收尾

執行 `scripts/postcheck.ps1 [-Drivers 名稱1,名稱2]`（唯讀，約 20 秒），確認版本與 build、啟用狀態、升級紀錄、有問題的裝置、之前懷疑的驅動是否正常載入、開機後的 Critical/Error 事件、TEMP/TMP 資料夾是否存在、Windows.old。計算 Windows.old 大小要好幾分鐘，需要時才加 `-WithOldSize`。

接著還原升級前的暫時性修改（TEMP/TMP、停用的服務、暫停的防護），並提醒：

- **RAM disk 使用者**：升級後確認 RAM disk 開機時仍會自動建立 TEMP 資料夾——升級可能讓 RAM disk 軟體的設定遺失，TEMP 指向不存在的資料夾會讓很多程式出錯。**請使用者重開機一次驗證**，再把 TEMP 改回去
- `Windows.old` 保留約 10 天可退回，確定穩定後再用「設定 → 系統 → 儲存空間 → 暫存檔案」清除
- 開機事件裡常見但通常無害的項目見 `references/scenarios.md` 的「升級後常見現象」

## 參考文件

| 檔案 | 何時讀 |
|---|---|
| `references/error-codes.md` | 拆解任何錯誤碼、延伸碼，或要給出對應建議時 |
| `references/log-guide.md` | 讀日誌、寫或調整監看條件、判斷某行訊息是不是問題時 |
| `references/scenarios.md` | 使用者問一般升級問題、網友常見狀況（卡 %、無限重開、特定軟體、ISO vs WU、26H2 等） |
| `references/case-study.md` | 想了解完整的真實診斷過程，或遇到「卡很久＋0xC1900101」類型時 |
