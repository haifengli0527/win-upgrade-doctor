# 升級錯誤碼對照

資料來源：Microsoft Learn〈Windows 10 upgrade error codes〉與〈Windows 10 upgrade resolution procedures〉（Win11 沿用同一套機制）。官方註明延伸碼可能隨版本調整，判讀時以日誌原文為準。

## 目錄

1. 錯誤碼的結構
2. 延伸碼：階段與作業
3. 0xC1900101 常見組合
4. 0x800xxxxx 常見組合
5. 相容性與安裝程式（MOSETUP）代碼
6. 其他常見代碼

## 1. 錯誤碼的結構

失敗時安裝程式會給兩個碼：**結果碼 - 延伸碼**，例如 `0xC1900101 - 0x4000D`。

- 結果碼開頭 `0x8` = Win32 錯誤（取後四碼查 Win32 error，例如 `0x80070070` → `0x70` = ERROR_DISK_FULL）
- 結果碼開頭 `0xC` = NTSTATUS / 安裝程式自訂碼
- 延伸碼：**第一位 = 階段，最後兩位 = 作業**（`0x4000D` = 階段 4、作業 0D）
- 只看到結果碼、沒有延伸碼：可能是用了抓不到延伸碼的工具（例如 Windows Update 介面）。去 Rollback 日誌找 `Reporting post reboot event -> [結果碼, 延伸碼]`
- **`0xC1900108`（MOSETUP_E_REPORTING）只是遙測用的重新對應**，日誌會寫 `Remapping install error [0xC1900101] -> [0xC1900108] for telemetry`，真正的錯誤是前面那個

## 2. 延伸碼：階段與作業

### 階段

| 碼 | 階段 | 白話 | 使用者看到的畫面 |
|---|---|---|---|
| 0 | UNKNOWN | 未知 | |
| 1 | DOWNLEVEL | 還在原本的系統裡準備 | 桌面上的安裝視窗、或背景執行 |
| 2 | SAFE_OS | 重開機進入暫時的精簡系統，套用新系統、搬資料 | 「正在處理更新」約 0–30% |
| 3 | FIRST_BOOT | 第一次開進新系統，裝驅動與功能 | 約 30–75% |
| 4 | OOBE_BOOT（常被稱為 SECOND_BOOT） | 第二次開機，套用設定與使用者資料 | 約 75–100% |
| 5 | UNINSTALL | 回滾 / 解除安裝 | 「正在還原先前的 Windows 版本」 |

畫面百分比與階段的對應是經驗值，不同版本會有差異。

### 作業

| 碼 | 作業 | 碼 | 作業 |
|---|---|---|---|
| 0 | UNKNOWN | 10 | ADD_DRIVER |
| 1 | COPY_PAYLOAD | 11 | ENABLE_FEATURE |
| 2 | DOWNLOAD_UPDATES | 12 | DISABLE_FEATURE |
| 3 | INSTALL_UPDATES | 13 | REGISTER_ASYNC_PROCESS |
| 4 | INSTALL_RECOVERY_ENVIRONMENT | 14 | REGISTER_SYNC_PROCESS |
| 5 | INSTALL_RECOVERY_IMAGE | 15 | CREATE_FILE |
| 6 | REPLICATE_OC | 16 | CREATE_REGISTRY |
| 7 | INSTALL_DRIVERS | 17 | BOOT |
| 8 | PREPARE_SAFE_OS | 18 | SYSPREP |
| 9 | PREPARE_ROLLBACK | 19 | OOBE |
| A | PREPARE_FIRST_BOOT | 1A / 1B | BEGIN / END_FIRST_BOOT |
| B | PREPARE_OOBE_BOOT | 1C / 1D | BEGIN / END_OOBE_BOOT |
| C | APPLY_IMAGE | 1E | PRE_OOBE |
| D | MIGRATE_DATA | 1F | POST_OOBE |
| E | SET_PRODUCT_KEY | 20 | ADD_PROVISIONING_PACKAGE |
| F | ADD_UNATTEND | | |

## 3. 0xC1900101 常見組合

`0xC1900101` 本身只代表「發生回滾」。官方說最常見的原因是驅動不相容，但**不要只靠這句就下結論**：使用者在升級途中強制關機，也會得到 0xC1900101，而且日誌裡沒有任何當機紀錄。

| 延伸碼 | 階段 / 作業 | 常見原因 | 建議 |
|---|---|---|---|
| 0x20004 | SAFE_OS / 安裝復原環境 | 過時的驅動、多餘的 SATA 裝置、防毒軟體 | 更新 BIOS 與驅動、移除沒用到的磁碟與裝置、暫時移除第三方防毒 |
| 0x2000C | SAFE_OS / 套用映像 | 過時驅動、磁碟或檔案系統損毀、ISO 損毀 | `chkdsk`、拔除周邊、重新下載 ISO、開啟動態更新 |
| **0x2000D** | SAFE_OS / 搬移資料 | **搬移的項目太多導致極慢，被使用者強制重開**；也可能是無法搬移的檔案或驅動 | 先看日誌最後在搬什麼。大量重複項目 → 清掉來源再重試（見案例） |
| 0x20017 | SAFE_OS / 開機 | 開進 SafeOS 時驅動出錯：儲存控制器（Intel RST、NVMe）、第三方磁碟加密、BIOS/TPM 設定、硬體故障 | 更新儲存驅動與 BIOS、暫停第三方加密、拔除多餘磁碟；看 setupact.log 找出問題驅動 |
| 0x30018 | FIRST_BOOT / SYSPREP | 某個裝置驅動在第一次開機時沒回應：防毒/EDR 過濾驅動、網路/Wi-Fi、顯示卡 | 拔除周邊、更新驅動、查 `Rollback\setupapi\setupapi.dev.log` |
| 0x3000D | FIRST_BOOT / 搬移資料 | 顯示卡驅動問題 | 更新或暫時移除顯示卡驅動 |
| 0x4000D | OOBE_BOOT / 搬移資料 | 驅動設定問題、使用者設定檔損壞 | 查 Rollback 日誌的 `Crash 0x… detected` 與 bugcheck 參數、看 `setupmem.dmp` |
| 0x40017 | OOBE_BOOT / 開機 | 第二次開機時驅動出錯，**典型是防毒或加密的過濾驅動** | 乾淨開機、暫停或移除防毒/加密/備份軟體的過濾驅動 |
| 0x4001E | OOBE_BOOT / PRE_OOBE | OOBE 前的一般性錯誤 | 一般排除流程 |

## 4. 0x800xxxxx 常見組合

| 代碼 | 意義 | 建議 |
|---|---|---|
| 0x8007042B - 0x4000D | 第二次開機搬資料時，某個程序意外結束 | 分析日誌找出無法搬移的檔案、程式或驅動 |
| 0x8007001F - 0x3000D | 第一次開機搬資料失敗，常和使用者設定檔有關 | 檢查 `ProfileList` 登錄裡已刪除帳號的殘留、`\Users` 下的無效設定檔 |
| 0x8007001F - 0x4000D | 某個裝置運作不正常 | 找出問題裝置，拔除、更新或更換 |
| 0x80070005 - 0x4000D | 搬資料時存取被拒 | 從日誌找出存取被拒的項目 |
| 0x80073BC3 / 0x80070002 / 0x80073B92 - 0x20009 | 分割區分析失敗，常見於**多顆磁碟上有多個系統分割區**（換新系統碟後舊碟還接著） | 暫時拔除或停用含舊系統分割區的磁碟 |
| 0x800704B8 - 0x3001A | 第一次開機的延伸錯誤 | 停用第三方防毒、拔除多餘裝置、乾淨開機 |
| 0x80070003 / 0x80070490 / 0x80040005 - 0x20007 | SafeOS 階段驅動安裝失敗 | 找出問題驅動 |
| 0x8007025D - 0x2000C | ISO 中繼資料損毀，或記憶體、儲存媒體有壞區 | 重新下載 ISO、檢測記憶體 |
| 0x80070070 / 0xC190020E | 空間不足 | 釋放 C: 空間（64 位元至少 20 GB，實務上建議 40 GB 以上） |
| 0x80070020 | 檔案被其他程序佔用 | 乾淨開機後重試 |
| 0x80070522 | 權限不足 | 用系統管理員身分執行 |
| 0x800F0922 | 常見於 EFI 系統分割區或復原分割區空間不足、VPN 干擾 | 檢查分割區大小、中斷 VPN（官方表未列，屬社群常見經驗） |

## 5. 相容性與安裝程式（MOSETUP）代碼

| 代碼 | 意義 | 處理 |
|---|---|---|
| 0xC1900107 | 上次安裝的清理還沒完成 | 重開機；不行就用「磁碟清理 → 清理系統檔案」 |
| 0xC1900200 / 0xC1900201 / 0xC1900202 | 不符合最低硬體需求 | 檢查 TPM 2.0、安全開機、CPU 支援清單 |
| 0xC1900204 | 無法用選定的方式升級（例如版別或語系不符，無法保留檔案） | ISO 的版別、語系、架構要和目前系統一致 |
| 0xC1900208 / 0xC1900209 | 有不相容的程式擋住升級 | 看 `Panther\CompatData_*.xml` 裡 `BlockingType="Hard"` 的項目 |
| 0xC1900216 | 有待處理的回滾 | 先讓回滾完成、重開機 |
| 0xC1900129 | 安裝程式會改用更新的版本繼續 | **正常行為**，等它重新啟動 |
| 0xC19001E1 | 安裝程序被暫停 | 檢查是否有東西暫停了 SetupHost |
| 0xC190011F / 0xC1900405 | 安裝程序當掉 | 看 setuperr.log 當下的錯誤 |

## 6. 其他常見代碼

| 代碼 | 意義 |
|---|---|
| 0x800705BB、0x800704D3（剛啟動 setup 時） | 通常伴隨安裝程式自我更新後重啟，先確認 SetupHost 是否換了 PID 並繼續寫日誌 |
| 0x80240017 | 這個版別無法升級，可能被組織原則擋住 |
| 0x80244018 | 透過 proxy 連線導致下載失敗 |
| 0x80190001 / 0x80246007 | 下載失敗，改用 ISO 或媒體建立工具 |
| 0xC1800118 | WSUS 內容缺少解密金鑰（企業環境） |
