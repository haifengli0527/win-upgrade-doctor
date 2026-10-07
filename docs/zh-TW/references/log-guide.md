# 升級日誌判讀指南

## 目錄

1. 日誌在哪裡
2. 讀大日誌的方法
3. 真正的警訊
4. 無害訊息清單（容易誤判）
5. 正常升級的階段時間軸
6. 監看條件的設計原則

## 1. 日誌在哪裡

| 時機 | 路徑 | 內容 |
|---|---|---|
| 準備中、SafeOS 階段 | `C:\$WINDOWS.~BT\Sources\Panther\setupact.log`、`setuperr.log` | 主日誌，可能長到數百 MB |
| 相容性掃描 | `C:\$WINDOWS.~BT\Sources\Panther\CompatData_*.xml` | `BlockingType="Hard"` 代表會擋住升級 |
| 回滾之後 | `C:\$WINDOWS.~BT\Sources\Rollback\setupact.log`、`setuperr.log` | **最終錯誤碼在這裡** |
| 回滾時的當機資訊 | `Rollback\setupmem.dmp`、`Rollback\*.evtx`、`Rollback\setupapi\setupapi.dev.log` | 0x30018 時看 setupapi |
| 升級成功後 | `C:\Windows\Panther\setupact.log`、`C:\Windows\Panther\NewOsSetup\` | |
| SetupDiag 自動分析 | `C:\Windows\Logs\SetupDiag\SetupDiagResults.xml` | 安裝程式失敗時會自動跑一次 SetupDiag |
| 升級紀錄 | 登錄 `HKLM\SYSTEM\Setup\Source OS (Updated on …)` | 每次完整升級留一筆舊版本資訊 |

注意：

- 路徑含 `$`，PowerShell 要用單引號或 `-LiteralPath`
- SafeOS 階段系統碟的代號常常不是 C:（日誌裡會看到 `F:\$WINDOWS.~BT`），這是正常的
- 下一次執行 setup 會覆蓋 `$WINDOWS.~BT`，**前一次的日誌要先備份**再重試

## 2. 讀大日誌的方法

- 不要整份載入。用 `Get-Content -Tail N`，或用 `[IO.File]::OpenText()` 逐行串流處理（約 1 分鐘可掃完 800 MB）
- 找最終結果：Rollback\setupact.log 搜 `Reporting post reboot event`、`Setup360Result`、`Current phase string`、`bugcheck`
- 找卡在哪：主日誌最後 200–500 行**重複最多的動作**與**被處理的路徑**。重複模式是 `MIG Processing File: <路徑>` 接 `RECAPPLY: Recursively applied … <路徑>` 時，代表正在逐一遷移檔案
- 算速度：數出某種項目被處理了幾筆、頭尾時間差，換算每筆耗時，再乘上剩餘數量

## 3. 真正的警訊

| 訊號 | 意義 |
|---|---|
| Rollback 日誌 `Initiating rollback/uninstall` | 已經在回滾 |
| `Reporting post reboot event -> [0xC19xxxxx, 0xNNNNN]` | 最終錯誤碼與延伸碼 |
| `Crash 0x… detected`、`Bugcheck parameter`、`Module name:` | 有當機，模組名稱就是嫌疑人 |
| `Current bugcheck string: <非 NULL>` | 有當機 |
| `setupmem.dmp` 存在 | 有當機傾印 |
| Error 行出現某個 `.sys` 驅動或某套軟體的名稱 | 才算是該軟體涉入的證據 |
| `CompatData_*.xml` 裡有 `BlockingType="Hard"` | 會被擋住，升級不會開始 |
| 主日誌**超過 15–30 分鐘完全沒有新行**，而且 SetupHost 的 CPU 不動 | 可能真的卡住了 |

## 4. 無害訊息清單（容易誤判）

以下訊息在成功的升級中也會出現，看到它們不要當成失敗或重開機訊號：

| 訊息 | 實際意思 |
|---|---|
| `IOCTL_STORAGE_QUERY_PROPERTY failed: 0x1` | 查詢磁碟屬性失敗，多顆磁碟或 RAID 時大量出現 |
| `IsRangeRequestSupported … 0x80040154` | 檢查下載伺服器是否支援分段下載 |
| `DU::CDUSession::Search … hr = 0x80070057` | 動態更新搜尋驅動時設定參數失敗，搜尋會照常進行 |
| `CheckUserInterrupt … 0x800704D3`、`ExecuteInstallMode … 0x800705BB`（剛啟動時） | 安裝程式自我更新後重啟，SetupHost 的 PID 會換掉 |
| `MoSetupPlatform: Restartable: [no]` | 這一段中斷後不能從中途接續，只是一個設定值 |
| `Rollback Enabled via scenario detection`、`RollbackOption`、`RollbackType`、`RollbackInitialize` | 預先準備好回滾的能力 |
| `OPERATIONTRACK: Enqueue Operation`、`Add phase`、`Operation (remaining)` 與步驟表格 | 安裝程式在排程或列印待辦步驟 |
| `CBS … Reboot required: no` | 某個元件處理完了，不需要重開 |
| `SYSPRP … (reboot requested)` | 新系統裡的設定模組「要等重開才生效」，是正常的 |
| `MIG Processing Registry: …Reboot Required` | 正在搬移名稱含有 Reboot 字樣的登錄機碼 |
| `CBS Failed to set hint EAs from the catalog` | Info 等級，寫入元件快取標記 |
| `WinSetupMon … GetNtPath … 0xC0000034`、`SETUPMON: Failed to install monitoring driver` | 監控驅動裝不起來，常因 TEMP 指到 SafeOS 裡不存在的磁碟。日誌會寫「rollback will continue」，**不是致命錯誤**，但代表 TEMP 設定值得修正 |
| `pSPRemoveUpgradeRegTree … gle=0x00000005` | 清除舊的升級登錄樹時權限不足 |
| `CSIAgent: Invalid xml format: "script" attribute is mandatory` | 遷移 XML 格式警告 |
| `MIG Plugin … TableTextServiceMig`、`BRIDGEMIG`、`WinsockMig`、`adammigrate.dll … 0x80070002` | 各種遷移外掛找不到要處理的東西 |
| `PITR … not found`、`Failed to remove PITR snapshots` | 舊版沒有這個元件 |
| `BFSVC: USE_EX_BINS flag is specified, but 2023 cert is not in db` | 安全開機憑證狀態訊息，不影響升級 |
| `Action progress: [100%]` 後馬上 `[0%]` | **每個步驟各自計算進度**，不是整體進度 |

## 5. 正常升級的階段時間軸

一次成功的 ISO 靜默升級（`/dynamicupdate enable`、SSD 系統碟、多顆傳統硬碟）實際觀察到的順序與時間。用來判斷「現在在哪、還要多久」：

| 相對時間 | 日誌特徵 | 說明 |
|---|---|---|
| 0 分 | `setup.exe`、`SetupPrep`、`SetupHost` 啟動 | |
| +1 分 | `0x800705BB` 等，SetupHost 換 PID | 自我更新後重啟 |
| +1–2 分 | `CompatData_*.xml` 產生 | 相容性掃描完成 |
| +4–11 分 | `FCDCATHelper: Transfer: [… %]` | 下載動態更新（數 GB，看網速） |
| +12–24 分 | `DUImageSandbox`、`Expanding express MumX`、`DPX phase: Apply Deltas` | 把累積更新解開、整合進新系統映像 |
| +31 分 | `DUImage: Searching for driver updates` | 搜尋驅動更新 |
| +32 分 | `Enqueue Operation` ×數十、`Add phase` 1–13 | 排定正式安裝的步驟 |
| +41 分 | `Executing operation: Gather data, scope: EVERYTHING` | **收集要遷移的資料**。正常約 5 分鐘；項目爆量時會在 SafeOS 拖上好幾小時 |
| +46 分 | `Register sync process`、`Backup the recovery partition` | 收尾 |
| +47–80 分 | `DPX`、`SXS Components preload`、`SYSPRP … Specialize_Offline` | 套用元件、設定新系統 |
| +88 分 | `Ensure suspended services are stopped`、`Install Eula` | 重開機前最後準備 |
| +89 分 | **`Executing operation: Orchestrate OS switch`** | **重開機前兆**，這個案例 2 分鐘後 SetupHost 結束、隨即重開 |
| 重開後（SafeOS） | 同一份 setupact.log 會繼續寫入，系統碟代號變成 F: 之類 | 回到桌面後，這份日誌在 `C:\Windows\Panther\setupact.log`，可以用來回放 |
| 重開後 | 「正在處理更新」0–100%，自動重開 2–3 次 | 這個案例約 10–15 分鐘就到登入畫面；一般預估 30–60 分鐘，最長約 90 分鐘 |

## 6. 監看條件的設計原則

從實際監看的誤報學到的：

- **只看等級為 Error 的行，再配合錯誤碼**判斷失敗（`0xC19…`、`SetupHost::Execute … Result = 0x8…`），加上 `Initiating rollback`。只要比對到 rollback、fail、reboot 這類字就報，會誤報一大堆
- 重開機前兆只認 `Executing operation:` 開頭、內容是 `Orchestrate OS switch` 或 `Prepare SafeOS` 的行
- 進度事件要節流（例如每 20% 一次），否則每秒都在通知
- 要有「日誌安靜太久」和「SetupHost 消失」的偵測，否則當掉時監看會沉默，看起來和正常一樣
- SetupHost 消失後先等 60 秒再判定，因為自我更新重啟時會短暫消失
