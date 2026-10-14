# 배관조종

안드로이드 폰·패드에서 라즈베리파이 배관 검사 화면을 전체 화면으로 보고 조종하는 앱입니다.

영상은 `http://<파이주소>/api/camera/mjpeg`, 상태는 `/ws/status`, 조종은 제어 페이지와 같은 `/api/motor`, `/api/led`, `/api/mission/*` 를 사용합니다. 기본 주소는 `192.168.1.157` (포트 80) 입니다.

## 화면

- 전체 화면 영상 위에 투명 스틱 두 개 (왼쪽: 전진·좌우, 오른쪽: 상승)
- 우상단 IMU 3D 자세
- 상단 LED 1·2 (크게) 와 3·4
- 가운데 정지
- 설정: 주소, 기록 시작/정지, 상태 점검, 카메라, RTC

폰과 라즈베리파이는 같은 Wi-Fi에 있어야 합니다.

## 실행

```bash
flutter pub get
flutter run
```

설치 파일:

```bash
flutter build apk --release
```
