#  VisionSync AI 

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" />
  <img src="https://img.shields.io/badge/TensorFlow_Lite-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white" />
  <img src="https://img.shields.io/badge/Google_ML_Kit-4285F4?style=for-the-badge&logo=google&logoColor=white" />
</p>

### **Precision Biometrics. Zero Proxies. Absolute Integrity.**

**VisionSync AI** is a cutting-edge attendance ecosystem developed for the AVCOE Hackathon. By merging **Edge-AI facial recognition** with **GPS Geo-fencing**, it creates a tamper-proof attendance loop that identifies students in milliseconds while ensuring they are physically on campus.

---

## 🚀 Key Features

* **⚡ On-Device Recognition:** Utilizes `MobileFaceNet` TFLite models to extract 192-D facial vectors locally—ensuring zero latency and data privacy.
* **📍 Geo-Fencing Security:** Integrated `Geolocator` validation. Attendance is rejected if the student is outside a **200m radius** of the campus.
* **🔐 Anti-Fraud Logic:** Prevents daily duplicate entries through Firestore-backed temporal validation.
* **📊 Behavioral Analytics:** Visualizes attendance consistency and weekly activity patterns using `fl_chart`.
* **☁️ Real-time Cloud Sync:** Instant Firestore updates for attendance logs and Firebase Storage for biometric profile management.

---

## 🛠️ System Architecture

### **The AI Pipeline**
1.  **Face Detection:** Google ML Kit identifies facial bounds and orientation.
2.  **Preprocessing:** Custom YUV420-to-RGB conversion & face-region cropping.
3.  **Vectorization:** MobileFaceNet generates a unique 192-point mathematical fingerprint.
4.  **Verification Engine:** * *Biometric:* Euclidean Distance calculation ($d \leq 1.25$).
    * *Spatial:* GPS cross-referencing with campus coordinates.
    * *Temporal:* Check for existing daily records to prevent double-marking.

---

## 📱 System Interface

<p align="center">
  <table border="0">
    <tr>
      <td align="center">
        <img src="https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/scan-face.svg" width="50" height="50" /><br/>
        <b>Authentication Terminal</b><br/>
        <i>Real-time AI & GPS Check</i>
      </td>
      <td align="center">
        <img src="https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/user-plus.svg" width="50" height="50" /><br/>
        <b>Biometric Enrollment</b><br/>
        <i>Face Vector Extraction</i>
      </td>
      <td align="center">
        <img src="https://cdn-icons-png.flaticon.com/512/8956/8956264.png" width="50" height="50" /><br/>
        <b>Behavior Analytics</b><br/>
        <i>Consistency Tracking</i>
      </td>
    </tr>
  </table>
</p>

---

## 📦 Installation

1. **Clone the Repo**
   ```bash
   git clone [https://github.com/PrashilD15/VisionSync.git](https://github.com/PrashilD15/VisionSync.git)
