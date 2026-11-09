# 🛸 Roblox 遊戲專案：《深空當舖》(Deep Space Pawn Shop) 開發指令

你現在是我們的 Roblox 遊戲主工程師兼系統架構師。我們正在開發一款類《深空當舖》（Deep Space Pawn Shop）的經營與鑑定遊戲。

### 🎮 遊戲核心機制簡介：
1. **客人登場**：外星客人帶著宇宙物品前來典當或出售。
2. **物品鑑定**：玩家使用工具（如 X 光、顯微鏡、成分分析儀）判斷物品真偽與品質（是否有裂痕、瑕疵、詛咒或偽造標誌）。
3. **數值議價**：玩家與客人進行互動議價，根據客人的「貪婪度」與「耐心值」決定成交價。
4. **經營與擴建**：賺取星幣（Credits）解鎖更高級的鑑定儀器、當舖裝潢與 Gamepass 功能。

---

## 🛠️ 技術架構規範 (Luau Guidelines)
- 使用 **Luau** 語言開發，採 **ModuleScript 模組化架構**。
- 資料存儲需預留 **ProfileService** 的整合介面。
- 嚴格遵守 **Client-Server 職責分離**：所有交易金額計算、真偽驗證、庫存變動必須在 Server 端處理，Client 端僅負責 UI 動畫與互動。

---

## 📋 請幫我們產出【第一階段：核心資料與系統模組】

請按順序為我們提供以下 3 個 ModuleScript 的完整程式碼，並附加詳細的註解：

### 1. `ItemDatabase.luau` (物品與真偽屬性模組)
- 請設計一個物品資料庫，包含至少 5 種風格獨特的宇宙物品（例如：宇宙怪獸牙齒、古老雷射槍、外星隕石核）。
- 每個物品結構需包含：
  - `ID`: 物品唯一識別碼
  - `Name`: 物品名稱
  - `Description`: 物品描述與背景故事
  - `BaseValue`: 基礎估值
  - `InspectionAttributes`: 鑑定特徵表（如：`isFake` 是否為假貨、`defectType` 瑕疵類型、`requiredTool` 需使用的鑑定工具）。

### 2. `BargainSystem.luau` (議價與 NPC 心態計算模組)
- 請寫出一個議價演算法 `BargainSystem.Negotiate(playerOffer, itemBaseValue, customerPatience, customerGreed)`。
- 邏輯要求：
  - 計算出客人的底線價格。
  - 當玩家出價低於底線時成交；高於底線時根據差額扣除 `customerPatience`（耐心值）。
  - 當耐心值歸零時，回傳 `DealFailed`（交易破局，客人離場）。
  - 回傳結果需包含：`Success (bool)`、`NewPatience (number)`、`NPCResponseText (string)`。

### 3. `PlayerDataSchema.luau` (玩家存檔資料結構)
- 定義玩家初始資料（`Credits` 星幣、`Reputation` 店鋪名聲、`UnlockedTools` 已解鎖工具表、`Inventory` 背包物品）。

---

請直接開始輸出上述 3 個 ModuleScript 的程式碼，並用清晰的代碼區塊呈現。
