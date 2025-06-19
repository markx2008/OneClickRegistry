# OneClickRegistry 私有映像倉庫部署說明

本專案提供「Traefik + Registry + Registry UI」一鍵安裝解決方案，適合需要自架私有 Docker Registry 並使用帳號密碼驗證Registry，提供給部屬服務拉取鏡像。
主要特色與條件如下：

1. Registry 需可供外部拉取映像，必須經由反向代理（如 Traefik）並強制走 443（HTTPS），否則 Docker 會報錯。
2. Registry 強制啟用帳號密碼驗證。
3. Registry UI 已處理跨域請求（CORS）問題，避免前端操作失敗。
4. 所有設定皆集中於 `.env`，可自訂三個服務的 port，並可透過一鍵腳本自動完成部署。


---

## 📁 專案結構

```
.
├── docker-compose.yml         # Docker 編排主設定
├── .env.example               # 環境變數範本
├── traefik/
│   └── middlewares.yml        # Traefik 中間件（認證設定）
├── registry/
│   ├── auth/                  # htpasswd 認證檔案存放處
│   └── data/                  # Docker 映像檔儲存（已被 .gitignore 排除）
├── .gitignore                 # 忽略敏感與執行時檔案
├── start.sh                   # 一鍵啟動腳本
└── README.md                  # 本文件（說明與操作指南）
```

---

## 🚀 快速開始

### 1. 複製並設定環境變數

```bash
cp .env.example .env
nano .env
```
請依需求修改 `.env` 內容，特別是 `REGISTRY_DOMAIN`、`REGISTRY_UI_DOMAIN`、`REGISTRY_PASSWORD` 及各服務 port。
範例參數說明：
- `REGISTRY_DOMAIN`：Registry 對外網域（如 registry.your-domain.com）
- `REGISTRY_UI_DOMAIN`：UI 對外網域（如 ui.your-domain.com）
- `TRAEFIK_WEB_PORT`、`REGISTRY_PORT`、`REGISTRY_UI_PORT`：可自訂三個服務的對應 port
- `REGISTRY_USER`、`REGISTRY_PASSWORD`：登入帳號密碼

---

### 2. 產生 Registry 帳號密碼檔

請先安裝 `apache2-utils`（或 `httpd-tools`），然後執行：

```bash
htpasswd -Bbn <你的帳號> <你的密碼> > registry/auth/htpasswd
```
> 例如：`htpasswd -Bbn myuser mypassword > registry/auth/htpasswd`

---

### 3. 啟動所有服務

請先賦予啟動腳本執行權限，然後執行：

```bash
chmod +x start.sh
./start.sh
```
此腳本會自動建立所需目錄、啟動 Traefik、Registry 及 Registry UI。

---

### 4. 設定 Cloudflare Tunnel（如需外部存取）

- 登入 Cloudflare 後台 → Zero Trust → Access → Tunnels。
- 建立新 Tunnel 並依指示於伺服器安裝 `cloudflared`。
- 在 Tunnel 的「Public Hostname」區段新增兩個主機名稱：
    - 主機名稱 1：`registry`（對應 `REGISTRY_DOMAIN`），指向 `localhost:8000`（或你設定的 port）
    - 主機名稱 2：`ui`（對應 `REGISTRY_UI_DOMAIN`），指向 `localhost:8000`
- 儲存設定。

---

### 5. 驗證服務

- UI 入口：`https://ui.your-domain.com`，可用瀏覽器開啟 Registry UI。
- 推送/拉取映像檔：
  ```bash
  docker login registry.your-domain.com
  ```
  輸入你在 `.env` 設定的帳號密碼即可。

---

### 6. 常見問題

- 若 Docker login 報錯，請確認 Registry 是否經由 HTTPS 反向代理，且 port 設定正確。
- 若 UI 操作出現 CORS 問題，請確認 `.env` 內 CORS 相關設定與 Traefik 設定檔。
- 內部測試可直接用 IP:port 存取，外部建議透過 Cloudflare Tunnel。

---

## ⚠️ 注意事項

- `registry/data/` 與 `registry/auth/` 目錄已被 `.gitignore` 排除，請勿將敏感資料提交至版本控制。
- 詳細設定與參數請參考各檔案內的註解說明。
- **一鍵部署**：只需一支腳本即可完成所有設定。
- **彈性自訂**：所有設定皆集中於 `.env` 檔案，方便管理。
- **CORS 處理**：已解決 UI 與 Registry API 間的跨域問題。

---

## 先決條件

1. **一個網域名稱**（如：`your-domain.com`）
2. **Cloudflare 帳號**（用於免費 Tunnel 服務）
3. **已安裝 Docker 與 Docker Compose 的伺服器/NAS**
4. 已安裝 `apache2-utils`（或 `httpd-tools`）以提供 `htpasswd` 指令

---

## 操作步驟

1. **下載專案原始碼**
    ```bash
    git clone <你的-repo-url>
    cd <repo-folder>
    ```

2. **設定環境變數**
    複製範本檔並依需求修改內容。
    ```bash
    cp .env.example .env
    nano .env
    ```
    **請務必修改 `REGISTRY_DOMAIN`、`REGISTRY_UI_DOMAIN` 與 `REGISTRY_PASSWORD`！**

3. **執行啟動腳本**
    此腳本會建立必要檔案並啟動所有服務。
    ```bash
    chmod +x start.sh
    ./start.sh
    ```

4. **設定 Cloudflare Tunnel**
    - 進入 Cloudflare 後台 → Zero Trust → Access → Tunnels。
    - 建立新 Tunnel 並依指示於伺服器安裝 `cloudflared`。
    - 在 Tunnel 的「Public Hostname」區段新增兩個主機名稱：
        - **主機名稱 1：**
            - 子網域：`registry`（或你設定的 `REGISTRY_DOMAIN`）
            - 網域：`your-domain.com`
            - 服務類型：`HTTP`
            - URL：`localhost:8000`（或你設定的 `TRAEFIK_WEB_PORT`）
        - **主機名稱 2：**
            - 子網域：`ui`（或你設定的 `REGISTRY_UI_DOMAIN`）
            - 網域：`your-domain.com`
            - 服務類型：`HTTP`
            - URL：`localhost:8000`（同上）
    - 儲存 Tunnel 設定。

5. **完成！**
    - UI 入口：`https://ui.your-domain.com`
    - 推送/拉取映像檔：`docker login registry.your-domain.com`

---

## 專案檔案說明

- `docker-compose.yml`：定義所有服務（Traefik、Registry、UI）
- `.env.example`：環境變數設定範本
- `start.sh`：一鍵部署與啟動腳本
- `traefik/`：Traefik 設定檔
- `registry/`：映像檔資料與認證檔案存放處