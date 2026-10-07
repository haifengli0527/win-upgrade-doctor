# win-upgrade-doctor

**Windows 功能更新（大版本升級）的 [Claude Code](https://docs.claude.com/claude-code) skill，也是一組可以單獨使用的 PowerShell 工具：升級前體檢、升級中監看日誌、失敗後診斷、升級後檢查。**

[English → README.md](README.md)

> **這不是微軟官方工具。** 它只讀取日誌和系統狀態，自己不會修改任何東西（除了掛載你指定的 ISO）；但就地升級會動到整台電腦，**請先備份**。使用風險自負（見 [LICENSE](LICENSE)）。

---

## 起因：「卡在 28%」六個小時

一台 Windows 11 從 23H2 升級到 26H2，反覆失敗，錯誤碼 `0xC1900101`。最後一次在「正在處理更新 28%」**停了好幾個小時**，最後被強制重開。最直覺的嫌疑犯是備份軟體的核心驅動，因為大家都說「0xC1900101 是驅動問題」。

日誌說的是另一回事：

| 日誌內容 | 意思 |
|---|---|
| `Reporting post reboot event -> [0xC1900101, 0x2000D]` | SAFE_OS 階段，**MIGRATE_DATA（搬移資料）** |
| `Current bugcheck string: NULL`、`No crash detected` | **完全沒有驅動當機** |
| 成千上萬行 `MIG Processing File: C:\Windows\SystemTemp\msedge_url_fetcher_…`，每筆約 0.5–1 秒 | 安裝程式在一個一個搬垃圾 |
| `C:\Windows\SystemTemp` 有 **31,959 項**，其中 31,451 個是空的 `chrome_url_fetcher_*` / `msedge_url_fetcher_*` 資料夾 | Chromium 系瀏覽器的更新程式三年來留下的 |

31,000 項 × 0.5–1 秒 ≈ 4–8 小時。它不是當機，只是很慢，是強制重開才觸發了回滾。刪掉那些空資料夾之後，同一個步驟只花了 **5 分鐘**，升級成功。備份軟體也不用移除。

這種空資料夾累積是 [Chromium 的已知問題](https://issues.chromium.org/issues/40283581)，[Brave 也有人回報每週 800–1000 個](https://github.com/brave/brave-browser/issues/46202)，但很少有人把它和升級失敗連起來。因為資料夾是空的，不佔硬碟空間，平常沒人發現，直到升級時必須一個一個處理。完整過程見[案例](docs/zh-TW/references/case-study.md)。

## 內容

| 部分 | 用途 |
|---|---|
| [`skills/win-upgrade-doctor/SKILL.md`](skills/win-upgrade-doctor/SKILL.md) | 給 Claude 的流程：判斷使用者在哪個階段、避免先入為主的判讀順序、信心程度標示、安全與同意規則 |
| [`references/error-codes.md`](skills/win-upgrade-doctor/references/error-codes.md) | 階段與作業對照表、常見的 `0xC1900101-0x…` 和 `0x800…` 組合、MOSETUP 代碼 |
| [`references/log-guide.md`](skills/win-upgrade-doctor/references/log-guide.md) | 日誌位置、真正的警訊、**20 多種看起來像錯誤其實無害的訊息**、一次實際升級的時間軸 |
| [`references/scenarios.md`](skills/win-upgrade-doctor/references/scenarios.md) | 卡在某個 %、無限重開、特定軟體（備份、防毒、加密、RAM disk、RST）、ISO 還是 Windows Update、24H2/25H2/26H2、無人值守升級、升級後的小問題 |
| [`scripts/preflight.ps1`](skills/win-upgrade-doctor/scripts/preflight.ps1) | 升級前體檢：SystemTemp 項目數並估算會多花的時間、TEMP/TMP 是否在 RAM disk、第三方過濾驅動、空間、待重開機、EFI 分割區、ISO 版別和語系是否相符 |
| [`scripts/watch.ps1`](skills/win-upgrade-doctor/scripts/watch.ps1) | 即時監看，只輸出值得回報的事件，重開機前約 2 分鐘預警。`-Replay` 可以回放已完成的日誌 |
| [`scripts/diagnose.ps1`](skills/win-upgrade-doctor/scripts/diagnose.ps1) | 失敗後：拆解延伸碼、判斷有沒有當機、最後在做什麼和速度、懷疑的軟體有沒有出現在 Error 行 |
| [`scripts/postcheck.ps1`](skills/win-upgrade-doctor/scripts/postcheck.ps1) | 升級後：版本、啟用、裝置、驅動、開機錯誤、TEMP 資料夾、Windows.old |

腳本全部**唯讀**（唯一的例外：`preflight.ps1 -IsoPath` 會掛載 ISO，並保持掛載供 setup.exe 使用），只用 ASCII 字元，Windows PowerShell 5.1 和 PowerShell 7 都能跑。

skill 本體是英文（Claude 會用使用者的語言回答）。繁體中文版在 [`docs/zh-TW/`](docs/zh-TW/SKILL.md)，內容相同，供閱讀參考。

## 安裝（Claude Code）

用 plugin 安裝：

```
/plugin marketplace add haifengli0527/win-upgrade-doctor
/plugin install win-upgrade-doctor@win-upgrade-doctor
```

或者把 [`skills/win-upgrade-doctor`](skills/win-upgrade-doctor) 複製到 `~/.claude/skills/`。

裝好後直接描述問題就好，例如：「Win11 升級一直 0xC1900101」、「卡在 28% 三個小時了」、「幫我看這台能不能升 26H2」。

## 不用 Claude，單獨使用腳本

用系統管理員身分開 PowerShell：

```powershell
cd skills\win-upgrade-doctor\scripts

# 升級前（可以順便檢查 ISO）
powershell -NoProfile -ExecutionPolicy Bypass -File .\preflight.ps1 -IsoPath D:\Win11.iso

# setup.exe 執行中（Ctrl+C 停止）
powershell -NoProfile -ExecutionPolicy Bypass -File .\watch.ps1

# 回滾之後（可以指定懷疑的驅動或軟體）
powershell -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -Suspects snapman,file_protector

# 升級成功後
powershell -NoProfile -ExecutionPolicy Bypass -File .\postcheck.ps1
```

## 誠實聲明：已知限制

- **只根據一個真實案例和官方文件整理。** 無害訊息清單和時間軸來自一次成功、一次失敗的升級。別台電腦會有別的雜訊，歡迎回報。
- **SafeOS、首次開機、OOBE 都沒辦法監看。** 那些階段不能執行第三方程式，所以監看在第一次重開機時就停了，Claude 也會斷線。能做的是重開前預警、回到桌面後診斷。
- **`diagnose.ps1` 只在合成的失敗日誌上測試過。** 真正失敗的那台電腦，日誌已經被成功的那次覆蓋掉了。非常歡迎提供（去敏感化後的）真實回滾日誌。
- **微軟沒有公開日誌格式。** 訊息文字可能隨版本改變。
- 錯誤碼說明改寫自 Microsoft Learn 並附上連結，判讀時一律以日誌原文為準。

## 參與貢獻

最有幫助的是附上日誌片段的問題回報。**貼上前請先遮蔽**：使用者名稱、電腦名稱、網域與網路名稱、Email、產品金鑰。測試方式見 [CONTRIBUTING.md](CONTRIBUTING.md)，不需要任何第三方套件。

## 授權

[MIT](LICENSE)
