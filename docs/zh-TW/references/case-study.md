# 案例：0xC1900101-0x2000D「卡在 28% 好幾小時」

已去除可識別資訊，只保留診斷需要的事實。

## 環境

- 桌上型電腦，6 核心工程版 CPU，GTX 1060，SSD 系統碟加上多顆傳統硬碟
- Windows 11 專業版 23H2（build 22631），要升級到 26H2（build 26300）
- 安裝了備份軟體（含檔案系統過濾驅動）與 RAM disk，使用者的 TEMP 和 TMP 都指向 RAM disk
- 用 Windows Update 和 ISO 都失敗過。最近一次重開機後卡在「28%」好幾個小時，使用者最後強制重開

## 使用者一開始的假設

「0xC1900101 是驅動問題，應該是備份軟體的核心驅動造成的，要不要整套移除？」

## 診斷過程

### 1. 從 Rollback 日誌直接取得錯誤碼

`Rollback\setupact.log` 裡有：

```
Reporting post reboot event -> [0xC1900101, 0x2000D]
Remapping install error [0xC1900101] -> [0xC1900108] for telemetry
Current phase string : SafeOS,Start
Current bugcheck string: NULL
No crash detected.
BsdSummarize … FatalErrorCode:0
```

結論：SAFE_OS 階段、MIGRATE_DATA 作業，**沒有任何當機紀錄**。所以不是驅動藍屏，不需要先下載 SetupDiag。

### 2. 看主日誌最後在做什麼

`Panther\setupact.log` 有 788 MB，最後幾千行全部是：

```
MIG  Processing File: C:\Windows\SystemTemp\msedge_url_fetcher_xxxx_yyyy
     RECAPPLY: Recursively applied (delayed execution): F:\Windows\SystemTemp\msedge_url_fetcher_xxxx_yyyy
```

每個項目大約 0.5–1 秒，從凌晨兩點一路搬到強制重開為止。

### 3. 算數量

`C:\Windows\SystemTemp` 有 **31,959** 個項目：

- `chrome_url_fetcher_*`：18,680 個
- `msedge_url_fetcher_*`：12,771 個
- 全部是**空資料夾**，0 個檔案、0 MB，從系統安裝一年半後開始累積，持續了三年

31,000 × 0.5–1 秒 ≈ 4–8 小時，和「卡在 28% 好幾小時」吻合。

這種累積是 Chromium 的已知問題（例如 Chromium issue 40283581，Brave 也有人回報每週 800–1000 個），但之前沒有人把它和升級失敗連起來。

### 4. 檢查被懷疑的軟體

備份軟體的名稱在主日誌出現了上千次，但**全部在相容性盤點和服務清單裡**（`BuildCache`、`IsWindowsProvider`），沒有任何一行是 Error。結論：和這次失敗沒有直接關係（高度懷疑），不需要移除。

### 5. 附帶發現

`setuperr.log` 有 `WinSetupMon::GetStablePath: Failed GetNtPath [<RAM disk>:\Tmp] (0xC0000034)`。原因是使用者的 TMP 指向 RAM disk，而 SafeOS 裡沒有這顆磁碟。這不是致命錯誤，但值得修正。

## 處理

1. 使用者關閉瀏覽器，自己刪除那些空資料夾（刪完 SystemTemp 剩 508 項）
2. 把 TEMP 和 TMP 暫時改回 C:
3. 備份軟體維持安裝，沒有移除
4. 用 ISO 執行 `setup.exe /auto upgrade /quiet /eula accept /dynamicupdate enable`

## 結果

- 「收集資料」這一步從**超過 6 小時縮短到 5 分鐘**
- 從啟動到重開機約 90 分鐘（包含下載 4 GB 動態更新），重開後十幾分鐘就看到登入畫面
- 升級到 26H2 成功，備份軟體的 6 個驅動全部正常載入
- 升級後發現 RAM disk 開機時不再自動建立 TEMP 資料夾，使用者在 RAM disk 軟體裡重新設定，重開機驗證後才把 TEMP 改回 RAM disk

## 學到的事

1. **0xC1900101 不等於驅動問題。** 先看有沒有 bugcheck；沒有的話，看日誌最後在做什麼
2. **「卡住」常常是「很慢」。** 要算的是項目數量，不是資料大小
3. **軟體名稱出現在日誌裡不等於它是兇手。** 要看它是不是出現在 Error 行
4. **TEMP 環境變數管不到 SYSTEM 身分的程式**，它們固定使用 `C:\Windows\SystemTemp`
5. **監看時的誤報很多。** `Restartable`、`Rollback Enabled`、`Reboot required: no`、進度歸零都不是警訊
6. **升級後要重開機驗證**和磁碟或驅動有關的自訂設定，例如 RAM disk
