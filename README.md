# Roblox 遊戲專案：《深空當舖》(Deep Space Pawn Shop) 開發


## 🎮 遊戲核心機制簡介：
客人登場：外星客人帶著宇宙物品前來典當或出售。
物品鑑定：玩家使用工具（如 X 光、顯微鏡、成分分析儀）判斷物品真偽與品質（是否有裂痕、瑕疵、詛咒或偽造標誌）。
數值議價：玩家與客人進行互動議價，根據客人的「貪婪度」與「耐心值」決定成交價。
經營與擴建：賺取星幣（Credits）解鎖更高級的鑑定儀器、當舖裝潢與 Gamepass 功能。
## 🛠️ 技術架構規範 (Luau Guidelines)
使用 Luau 語言開發，採 ModuleScript 模組化架構。
資料存儲需預留 ProfileService 的整合介面。
嚴格遵守 Client-Server 職責分離：所有交易金額計算、真偽驗證、庫存變動必須在 Server 端處理，Client 端僅負責 UI 動畫與互動。

# 一、 核心玩法迴圈 (Core Gameplay Loop)
客人登場 (Customer Arrival)： 外星人、太空海盜、流浪商人帶著各種宇宙廢料、外星遺物前來典當或出售。
物品鑑定 (Item Inspection)：
使用工具（掃描儀、紫外線光、成分分析儀）檢查物品特徵。
判斷是否為「真品」、「贗品（Fake）」、「危險違禁品」或「帶有詛咒/特殊能量」。
砍價與交易 (Bargaining & Transaction)：
根據物品狀況、客人的心理耐心值（Patience）進行出價與議價。
低價買入、高價賣給特定買家或收藏家。
店鋪升級與探索 (Upgrades & Expansion)：
賺取星幣（Credits），購買更高級的鑑定儀器、擴建店面、雇用員工，或解鎖宇宙暗網交易。
##💰 課金要素植入 (Monetization Strategy)
這類經營鑑定遊戲可以非常自然地融入 Robux 課金，且不會破壞免費玩家的體驗：

1. Gamepass (永久功能 / VIP)
高級天眼掃描儀 (VIP Scanner)： 永久顯示物品的「隱藏瑕疵機率」或直接標示 5% 的估值誤差範圍。
讀心術 / 客人性格透視 (Empath Glasses)： 永久顯示客人的最高/最低心理底線（更容易砍到最低價）。
雙倍店鋪名聲 (2x Reputation)： 吸引更多高單價、稀有外星客前來。
宇宙倉庫擴建 (Extra Storage Slots)： 允許囤積更多待價而沽的稀有寶物。
2. Developer Products (消耗品 / 轉蛋)
神秘星際貨櫃 (Gacha Containers)： 花費 Robux 直接購買開箱，隨機獲得「傳說級外星神器」（可擺在店裡展示或賣出巨款）。
即時鑑定速查表 (Instant Auth Pass)： 跳過鑑定小遊戲，直接得出 100% 精確真偽結果與市值。
星幣包 (Credit Packs)： 快速補充營運資金，避免破產。

##🛠️ 如何讓 Claude 幫你們寫這款遊戲？
你們可以把開發拆分成以下模組，逐一讓 Claude 產出程式碼與資料表：

1. 物品與鑑定資料庫 (Item Data Module)
讓 Claude 產生大量的外星物品資料結構（包含名稱、基礎價值、偽造特徵、鑑定方法）。

給 Claude 的 Prompt 範例： 「請幫我用 Luau 撰寫一個 ItemDatabase ModuleScript。定義 10 種深空當舖的物品（包含稀有度、估價、真實度 isFake 屬性，以及 3 種鑑定條件，例如：需要用 X 光掃描才會發現裂痕）。」

2. 議價與 NPC 心態系統 (Bargain Logic)
讓 Claude 撰寫計算公式：根據客人的貪婪度、耐心值與玩家的出價幅度，決定 NPC 是接受、拒絕還是摔門離開。

給 Claude 的 Prompt 範例： 「幫我寫一個伺服器端的議價邏輯函式 CalculateBargain(customerPatience, baseValue, playerOffer)，傳回 NPC 是否同意交易，以及耐心值的扣減演算法。」

3. 鑑定小遊戲 logic (Inspection Minigames)
例如：點擊特定區域掃描輻射值、比對圖鑑上的外星符號是否一致。

📋 建議團隊第一步
確定視覺風格： 要走低多邊形科幻風（Low-Poly Sci-Fi），還是復古像素 / 復古未來的 2D/3D 混合風格？
在 Roblox Studio 拉出基本場景： 只需要一個當舖櫃檯、一個展示架，以及客人站在櫃檯前的位置。
開始撰寫 ItemDatabase 模組： 讓 Claude 幫你們設計第一批 20 種有趣的太空物品與怪異故事！
你們想先從物品屬性結構設計開始，還是先寫議價系統的程式碼呢？
