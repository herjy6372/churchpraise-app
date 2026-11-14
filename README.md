# churchpraise

교회 예배·찬양팀을 위한 새찬송가 & CCM 악보 뷰어 앱 (Flutter, Android / iOS).

자세한 소개는 [PORTFOLIO.md](PORTFOLIO.md)를 참고하세요.

- 포트폴리오 사이트: [herjy6372.github.io/portfolio](https://herjy6372.github.io/portfolio/)

## 스크린샷

| 성경 | 새찬송가 | 예배문 |
|:---:|:---:|:---:|
| <img src="docs/screenshots/bible.jpg" width="240" alt="성경 탭"> | <img src="docs/screenshots/hymns.jpg" width="240" alt="새찬송가 탭"> | <img src="docs/screenshots/liturgy.jpg" width="240" alt="예배문 탭"> |

## 저장소에 포함되지 않은 파일

저작권 문제로 다음 콘텐츠는 이 저장소에 포함하지 않습니다.

- `assets/hymns_pdf/` — 새찬송가 악보 PDF
- `assets/bible/` — 성경 본문 데이터

빌드하려면 위 경로에 해당 파일을 직접 준비해야 합니다.

릴리스 서명 파일(`android/key.properties`, `android/app/upload-keystore.jks`)도 포함되지 않습니다.

## 빌드

```bash
flutter pub get
flutter run
```
