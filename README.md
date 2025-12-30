# Grup37_MicroProje

![Project Status](https://img.shields.io/badge/Status-Development-yellow)
![Microcontroller](https://img.shields.io/badge/MCU-PIC16F877A-blue)
![Language](https://img.shields.io/badge/Language-Assembly%20%2F%20Python-green)
![Simulation](https://img.shields.io/badge/Simulation-PICSimLab-orange)

Bu proje, **ESOGÜ Bilgisayar Mühendisliği "Introduction to Microcomputers"** dersi (2025-2026 Güz) dönem projesi kapsamında geliştirilmiştir. Proje, iki ayrı PIC16F877A mikrodenetleyicisi ve bir PC istemci uygulaması kullanarak sensör tabanlı bir ev otomasyon sistemini simüle eder.

## 📋 Proje Özeti

Sistem, UART üzerinden haberleşen üç ana bileşenden oluşur:
1.  **Board #1 (Klima Sistemi):** Sıcaklık kontrolü, fan hızı yönetimi ve kullanıcı giriş arayüzü.
2.  **Board #2 (Perde & Çevre Kontrolü):** Işık/Basınç sensörleri ve perde motor kontrolü.
3.  **PC İstemcisi (Client):** Sistemi uzaktan izleyen ve yöneten masaüstü uygulaması.

---

## 🛠 Donanım Mimarisi (PICSimLab)

Simülasyon için **PICSimLab** ve **gpboard** kullanılmaktadır.

| Özellik | Board #1: Klima Kontrol Ünitesi | Board #2: Perde Kontrol Ünitesi |
| :--- | :--- | :--- |
| **MCU** | PIC16F877A | PIC16F877A |
| **Sensörler** | LM35 Sıcaklık, Takometre (Fan) | LDR (Işık), BMP180 (Basınç/Sıcaklık) |
| **Aktüatörler** | Isıtıcı, Soğutucu, DC Fan | Step Motor (Perde) |
| **Arayüz** | 4x4 Keypad, 7-Segment Display | 2x16 LCD, Rotary Potentiometer |
| **Haberleşme** | UART (Serial) | UART (Serial) |

---

## 📡 İletişim Protokolü

Sistem **9600 baud rate** ve **8N1** formatında haberleşir.

### Board #1 (Klima) Komut Seti

| Komut (Binary) | Açıklama |
| :--- | :--- |
| `00000001` | İstenen Sıcaklık (Ondalık Kısım) Getir |
| `00000010` | İstenen Sıcaklık (Tam Sayı Kısım) Getir |
| `00000011` | Ortam Sıcaklığı (Ondalık Kısım) Getir |
| `00000100` | Ortam Sıcaklığı (Tam Sayı Kısım) Getir |
| `00000101` | Fan Hızını Getir (rps) |
| `10xxxxxx` | İstenen Sıcaklık Ayarla (Ondalık - 6 bit) |
| `11xxxxxx` | İstenen Sıcaklık Ayarla (Tam Sayı - 6 bit) |

### Board #2 (Perde) Komut Seti

| Komut (Binary) | Açıklama |
| :--- | :--- |
| `00000001` | İstenen Perde Durumu (Ondalık) |
| `00000010` | İstenen Perde Durumu (Tam Sayı) |
| `00000011` | Dış Sıcaklık (Ondalık) |
| `00000100` | Dış Sıcaklık (Tam Sayı) |
| `00000101` | Dış Basınç (Ondalık) |
| `00000110` | Dış Basınç (Tam Sayı) |
| `00000111` | Işık Şiddeti (Ondalık) |
| `00001000` | Işık Şiddeti (Tam Sayı) |
| `10xxxxxx` | Perde Durumu Ayarla (Ondalık - 6 bit) |
| `11xxxxxx` | Perde Durumu Ayarla (Tam Sayı - 6 bit) |

---

## 🚀 Kurulum ve Çalıştırma

### Gereksinimler
* [PICSimLab](https://lcgamboa.github.io/picsimlab/) (v0.9.2+)
* **Sanal Seri Port Sürücüsü:** Windows için `com0com`, Linux için `tty0tty`.
* **Derleyiciler:** MPASM (Assembly), Python 3.x veya GCC (PC Uygulaması).

### Adımlar
1.  **Sanal Portları Ayarlayın:** `COM1` <-> `COM2` ve `COM3` <-> `COM4` çiftlerini oluşturun.
2.  **PICSimLab'ı Başlatın:**
    * **Board 1:** `.hex` dosyasını yükleyin, Seri Port: `COM2`.
    * **Board 2:** `.hex` dosyasını yükleyin, Seri Port: `COM4`.
3.  **PC Uygulamasını Çalıştırın:**
    * Uygulama üzerinden `COM1` ve `COM3` portlarına bağlanın.

---

## 📂 Dosya Yapısı

```text
.
├── src/
│   ├── board1_assembly/   # Klima Kontrol Ünitesi (.asm)
│   ├── board2_assembly/   # Perde Kontrol Ünitesi (.asm)
│   └── pc_application/    # PC Arayüzü ve API (Python/C++)
├── docs/                  # Proje Raporu ve Şemalar
├── simulation/            # PICSimLab Workspace dosyaları
├── .gitignore
└── README.md
