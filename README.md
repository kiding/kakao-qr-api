# kakao-qr-api

<img src="images/shortcuts.gif" width=400>

원격으로 카카오 계정에 로그인한 후 QR 체크인 데이터를 반환하는 API를 구성합니다. AWS Lambda 상에서 인증을 처리하므로 스마트폰 잠금 해제 후 카카오톡 앱을 여는 과정 없이 QR을 생성할 수 있습니다. iOS 단축어(Shortcuts) 앱 등 자동화에 활용할 수 있습니다.

[jeyraof/covid-19-qr-ios14-back-tap](https://github.com/jeyraof/covid-19-qr-ios14-back-tap)에서 아이디어를 얻었습니다.

## 사용 방법

카카오톡 앱의 QR 체크인 서비스를 사용하여 인증 및 동의 과정을 최초 한번 이상 거친 경우에만 사용할 수 있습니다.

### API 배포

* [Amazon Web Services](http://aws.amazon.com) 계정과 [액세스 키 정보](https://docs.aws.amazon.com/ko_kr/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-creds)가 필요합니다.
* 2단계 인증이 설정되지 않은 [카카오 계정](https://accounts.kakao.com) 사용자명과 비밀번호가 필요합니다. 
  * 생성될 AWS Lambda의 환경 변수에 평문으로 저장됩니다.
* `deploy.sh` 스크립트 대신 AWS Console에서 동일하게 수행해도 무방합니다.
* 배포된 URL로 `X-API-KEY` 헤더와 함께 HTTP `GET` 요청하여 반환된 데이터를 QR로 변환하면 체크인이 가능합니다.

```bash
git clone https://github.com/kiding/kakao-qr-api.git
pushd kakao-qr-api
chmod +x deploy.sh
./deploy.sh
```

<img src="images/deploy.png" width=500>

```bash
curl https://mt13bw176c.execute-api.ap-northeast-2.amazonaws.com/default \
  -H 'X-API-KEY: u03AIUqgML7hqSr6FIFhz1cf5yNX2lKG2fiYnLeT'
# 002|eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJmZWZhZmJmMGYxZjJmM2Y0ZjVmNmY3ZjhkZWFkYmVlZiIsImlzcyI6Imtha2FvdGFsayIsImV4cCI6MTYwMTc0OTQ2MSwidmVyc2lvbiI6IjAwMiJ9.KMqieVSWm5dO5ZdTKmjrsWmqbmgxiO3xOgbYgu53zvM
```

### 자동화 예시: iOS 단축어(Shortcuts)

<img src="images/shortcuts.png" width=400>
