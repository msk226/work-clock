# 출시 절차

v1.0.0 기준. 공개 전환과 푸시는 확인한 뒤에 한다.

## 1. 공개 전 확인

```sh
./build.sh --no-install
./tests/run.sh
git ls-files                    # config.json 같은 실제 설정이 없는지 확인
git log -p | grep -iE "monthlyPay|annualSalary" # 가짜 값(tests/fixtures, README)만 있는지 확인
```

## 2. 소스 저장소 공개와 태그

```sh
gh repo edit msk226/work-clock --visibility public --accept-visibility-change-consequences
git tag v1.0.0
git push origin v1.0.0
```

## 3. tarball sha256

GitHub가 만든 tarball의 해시를 써야 한다. 로컬 `git archive` 결과와 다를 수 있다.

```sh
curl -fsSL https://github.com/msk226/work-clock/archive/refs/tags/v1.0.0.tar.gz | shasum -a 256
```

## 4. tap 저장소

`~/Desktop/Code/homebrew-tap/Formula/workclock.rb`의 `REPLACE_WITH_TARBALL_SHA256`을 3번 값으로 바꾼다.

```sh
cd ~/Desktop/Code/homebrew-tap
gh repo create msk226/homebrew-tap --public --source . --remote origin --push
```

## 5. 설치 확인

```sh
brew tap msk226/tap
brew install workclock
brew test workclock
brew audit --strict --online workclock
```

## 다음 버전

1. `main.swift`의 `appVersion`을 올린다.
2. 태그를 달고 푸시한다.
3. formula의 `url`과 `sha256`을 바꿔 tap 저장소에 푸시한다.
