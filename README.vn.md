# ZaloClaw Infra 🚀

Dựng môi trường OpenClaw bằng Docker trong vài phút, có sẵn định tuyến model thông minh và mấy tool cần thiết để xài liền.

> [!IMPORTANT]
> ⚡ **Bạn muốn quy trình thiết lập Zalo nhanh nhất?** Hãy dùng dự án UI đồng hành tại đây: **[zaloclaw-ui](https://github.com/zaloclaw/zaloclaw-ui)**.

![Lợi ích ZaloClaw](image/README/Zclawbenefit.png)

## Repo này để làm gì 🎯

Repo này sinh ra để việc cài OpenClaw và chạy từ ngày đầu đỡ cực hơn, tập trung vào 3 mục tiêu chính:

1. Dựng OpenClaw trong Docker bằng script, chạy đi chạy lại vẫn ổn định.
2. Dùng LiteLLM router để đẩy request sang model rẻ hơn khi hợp lý, không phải lúc nào cũng đốt tiền vào model đắt.
3. Cài sẵn tool và runtime dependency hay dùng trong gateway container, gồm Playwright và gog CLI.

## Có gì sẵn cho bạn ✨

- 🐳 Tự động dựng và chạy OpenClaw Docker.
- 🧠 Tạo cấu hình LiteLLM từ API key bạn đã khai báo.
- ⚙️ Seed sẵn cấu hình OpenClaw cho browser, gateway, models, plugins, agents và skills.
- 🎭 Cài dependency Linux cho Playwright và Chromium.
- 🛠️ Cài gog CLI ngay trong gateway container đang chạy.

## Cần chuẩn bị trước 📦

- Máy dùng shell macOS hoặc Linux
- Docker + Docker Compose
- Ít nhất một API key của nhà cung cấp model (OpenAI, Google, Anthropic hoặc OpenRouter)

## Cài Docker Desktop trên macOS 🍎

Nếu máy bạn chưa có Docker, làm nhanh theo mấy bước này:

1. Vào trang tải Docker Desktop: https://www.docker.com/products/docker-desktop/
2. Chọn đúng bản cho máy Mac của bạn:
	- Apple Silicon (M1, M2, M3...)
	- Intel Chip
3. Tải file .dmg, mở lên rồi kéo Docker vào Applications.
4. Mở Docker Desktop lần đầu và cấp quyền khi macOS hỏi (network, privileged helper, v.v.).
5. Chờ Docker báo trạng thái Running.

Kiểm tra cài đặt đã ổn chưa:

```bash
docker --version
docker compose version
```

Nếu cả 2 lệnh đều ra version thì máy bạn đã sẵn sàng để chạy script setup.

## Bắt đầu nhanh ⚡

### 1) Chuẩn bị file môi trường 🧩

Tạo file .env:

```bash
cp .env.example .env
```

Sau đó sửa .env và điền tối thiểu mấy biến này:

- OPENCLAW_CONFIG_DIR
- OPENCLAW_WORKSPACE_DIR
- LITELLM_MASTER_KEY
- Một API key nhà cung cấp, ví dụ OPENAI_API_KEY, GOOGLE_API_KEY, ANTHROPIC_API_KEY hoặc OPENROUTER_API_KEY

Script sẽ check mấy biến này, thiếu là dừng ngay và báo lỗi rõ ràng.
Mấy biến còn lại trong .env.example (như port, image tag) cứ để mặc định cũng được.

### 2) Chạy script setup ▶️

```bash
chmod +x zaloclaw-docker-setup.sh
./zaloclaw-docker-setup.sh
```

Script này sẽ lo trọn gói các bước setup:

- Tạo cấu hình LiteLLM dựa trên API key bạn có.
- Seed cấu hình OpenClaw với mặc định hợp lý.
- Khởi chạy OpenClaw gateway bằng Docker Compose.
- Cài dependency hệ thống cho Playwright.
- Cài Chromium cho Playwright.
- Cài gog CLI trong gateway container.

## Setup xong bạn có gì ✅

Bạn sẽ có:

- 🐳 OpenClaw gateway chạy ổn trong Docker.
- 🧭 LiteLLM smart router hoạt động để chọn model theo độ phức tạp tác vụ.
- 🎭 Playwright + Chromium sẵn sàng cho các workflow tự động hóa trình duyệt.
- 🛠️ gog CLI dùng được ngay trong gateway container.

Muốn xem log thì chạy:

```bash
docker compose logs -f openclaw-gateway
```

## Lưu ý nhỏ 📝

- Chạy lại script thì nó sẽ tận dụng cấu hình có sẵn khi có thể.
- Nhớ giữ kín file .env, đừng commit API key thật lên repo.

## Tác giả 👤

- Tên: Hưng Nguyễn
- Mô tả: Đam mê AI, thích tự động hóa và đơn giản mọi thứ
