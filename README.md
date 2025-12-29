
# 📱 QR Automation Studio

**QR Automation Studio** is a powerful Flutter application designed to automate the bulk generation of QR code cards. Whether you are generating hotel room keys, event tickets, or inventory labels, this tool allows you to overlay unique QR codes and text onto a custom design template and export them as a batch.

---

## ✨ Key Features

* **📂 Dual Data Sources:**
* **CSV Upload:** Import thousands of rows of data.
* **Pattern Generator:** Create sequences (e.g., `Room-101` to `Room-150`) without needing a spreadsheet using the `*` wildcard system.


* **🎨 Visual Editor:**
* **Drag & Drop:** Position your QR code and text simply by dragging them across your template.
* **Live Preview:** See exactly how your card looks before generation.


* **✨ Rich Customization:**
* Adjust QR size and Text size via sliders.
* Choose from popular Google Fonts or upload a **Custom Font (.ttf)**.
* Toggle Bold/Italic styles and customize text colors.


* **⚡ High-Performance Batching:** Generates hundreds of high-quality PNGs in seconds.
* **📦 ZIP Export:** Automatically zips all generated images for easy sharing or saving.

---

<!-- ## 📸 Screenshots

| Dashboard | Visual Editor | Pattern Generator |
| --- | --- | --- |
| *(Add screenshot here)* | *(Add screenshot here)* | *(Add screenshot here)* |

--- -->

## 🚀 Getting Started

### Prerequisites

* [Flutter SDK](https://flutter.dev/docs/get-started/install) installed.
* An Android/iOS emulator or physical device.

### Installation

1. **Clone the repository:**
```bash
git clone https://github.com/abhimanyus1997/qr-automation-studio.git
cd qr-automation-studio

```


2. **Install dependencies:**
```bash
flutter pub get

```


3. **Run the app:**
```bash
flutter run

```



---

## 📖 Usage Guide

### 1. Data Source Selection

#### Option A: CSV Upload

Create a `.csv` file with the following **required headers**:

* `id` (Used for the filename)
* `text` (The visible label on the card)
* `url` (The data embedded in the QR code)

**Example CSV:**

```csv
id,text,url
file_1,Room 101,https://hotel.com/checkin/101
file_2,Room 102,https://hotel.com/checkin/102

```

#### Option B: Pattern Generator

Use the built-in generator to create sequential data. Use `*` as a wildcard for the number.

* **URL:** `https://mysite.com/ticket-*`
* **Text:** `Seat Number *`
* **Range:** Start `1` to End `50`
*(This will generate Seat Number 1, Seat Number 2, etc.)*

### 2. Template

Upload any image (PNG/JPG) to serve as the background card.

### 3. Visual Editor

* Click **"Open Visual Editor"**.
* Drag the QR code and Text to the desired location on your template.
* Use the tabs to change fonts, colors, and sizes.

### 4. Generate

* Click **"Generate All Files"**.
* Once processing is complete, share or save the resulting **ZIP file**.

---

## 🛠️ Tech Stack & Dependencies

* **Framework:** Flutter & Dart
* **UI/UX:** Material 3 Design
* **Core Packages:**
* [`qr_flutter`](https://www.google.com/search?q=%5Bhttps://pub.dev/packages/qr_flutter%5D(https://pub.dev/packages/qr_flutter)) - QR rendering.
* [`csv`](https://www.google.com/search?q=%5Bhttps://pub.dev/packages/csv%5D(https://pub.dev/packages/csv)) - Data parsing.
* [`archive`](https://www.google.com/search?q=%5Bhttps://pub.dev/packages/archive%5D(https://pub.dev/packages/archive)) - ZIP file creation.
* [`file_picker`](https://www.google.com/search?q=%5Bhttps://pub.dev/packages/file_picker%5D(https://pub.dev/packages/file_picker)) - File selection.
* [`google_fonts`](https://www.google.com/search?q=%5Bhttps://pub.dev/packages/google_fonts%5D(https://pub.dev/packages/google_fonts)) - Typography.
* [`share_plus`](https://www.google.com/search?q=%5Bhttps://pub.dev/packages/share_plus%5D(https://pub.dev/packages/share_plus)) - Export functionality.



---

## 👤 Author

**Abhimanyu Singh**

* *Software Developer | AI & Mobile Enthusiast*
* Currently working on Generative AI, RAG Pipelines, and Mobile Apps.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.