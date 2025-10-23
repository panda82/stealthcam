mkdir -p .github/workflows
cat > .github/workflows/android.yml <<'YAML'
name: Android CI
on:
  push:
    branches: ["main"]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - name: Set up Android SDK
        uses: android-actions/setup-android@v3
        with:
          accept-android-sdk-licenses: true
          cmdline-tools-version: 11076708

      - name: Install SDK packages (with fallback)
        shell: bash
        run: |
          set -euxo pipefail
          sdkmanager --list || true
          sdkmanager "platform-tools" || true
          if ! sdkmanager "platforms;android-34"; then
            LATEST_PLATFORM="$(sdkmanager --list | sed -n 's/^[[:space:]]*\(platforms;android-[0-9]\+\).*/\1/p' | sort -V | tail -1)"
            sdkmanager "${LATEST_PLATFORM}"
            USING_API="${LATEST_PLATFORM##*android-}"
          else
            USING_API="34"
          fi
          if ! sdkmanager "build-tools;34.0.0"; then
            LATEST_BT="$(sdkmanager --list | sed -n 's/^[[:space:]]*\(build-tools;[0-9][0-9.]*\).*/\1/p' | sort -V | tail -1)"
            sdkmanager "${LATEST_BT}"
          fi
          echo "USING_API=${USING_API}" >> "$GITHUB_ENV"

      - name: Detect Gradle project root
        id: detect
        shell: bash
        run: |
          set -e
          ROOT="$(git ls-files | grep -E '(^|/)(settings\.gradle(\.kts)?|build\.gradle(\.kts)?)$' | xargs -r -n1 dirname | sort -u | head -n1)"
          [ -n "$ROOT" ] || { echo "No Gradle settings/build file found"; exit 1; }
          echo "root=$ROOT" >> "$GITHUB_OUTPUT"

      - name: Align compile/target SDK if fallback used
        if: env.USING_API != '34'
        shell: bash
        run: |
          API="${USING_API}"
          ROOT="${{ steps.detect.outputs.root }}"
          sed -i "s/compileSdkVersion [0-9][0-9]*/compileSdkVersion ${API}/" "$ROOT/app/build.gradle" || true
          sed -i "s/targetSdkVersion [0-9][0-9]*/targetSdkVersion ${API}/" "$ROOT/app/build.gradle" || true

      - name: Install Gradle 8.4 via SDKMAN
        shell: bash
        run: |
          curl -s "https://get.sdkman.io" | bash
          source "$HOME/.sdkman/bin/sdkman-init.sh"
          sdk install gradle 8.4
          gradle --version

      - name: Build Debug APK
        shell: bash
        run: |
          set -euxo pipefail
          cd "${{ steps.detect.outputs.root }}"
          gradle assembleDebug --stacktrace --warning-mode all --info

      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: StealthCam-debug
          path: ${{ steps.detect.outputs.root }}/app/build/outputs/apk/debug/*.apk
YAML

git add .github/workflows/android.yml
git rebase --continue
git add .github/workflows/android.yml
git commit -m "Resolve merge conflict in workflow"
git push
# Generează wrapper compatibil cu AGP 8.2.2
gradle wrapper --gradle-version 8.4
git add gradlew gradlew.bat gradle/wrapper/gradle-wrapper.properties gradle/wrapper/gradle-wrapper.jar
git commit -m "Add Gradle wrapper 8.4"
git push
mkdir -p .github/workflows
cat > .github/workflows/android.yml <<'YAML'
name: Android CI
on:
  push:
    branches: ["main"]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - name: Set up Android SDK
        uses: android-actions/setup-android@v3
        with:
          accept-android-sdk-licenses: true
          cmdline-tools-version: 11076708

      - name: Install SDK packages (with fallback)
        shell: bash
        run: |
          set -euxo pipefail
          sdkmanager --list || true
          sdkmanager "platform-tools" || true
          if ! sdkmanager "platforms;android-34"; then
            LATEST_PLATFORM="$(sdkmanager --list | sed -n 's/^[[:space:]]*\(platforms;android-[0-9]\+\).*/\1/p' | sort -V | tail -1)"
            sdkmanager "${LATEST_PLATFORM}"
            USING_API="${LATEST_PLATFORM##*android-}"
          else
            USING_API="34"
          fi
          if ! sdkmanager "build-tools;34.0.0"; then
            LATEST_BT="$(sdkmanager --list | sed -n 's/^[[:space:]]*\(build-tools;[0-9][0-9.]*\).*/\1/p' | sort -V | tail -1)"
            sdkmanager "${LATEST_BT}"
          fi
          echo "USING_API=${USING_API}" >> "$GITHUB_ENV"

      - name: Detect Gradle project root
        id: detect
        shell: bash
        run: |
          set -e
          ROOT="$(git ls-files | grep -E '(^|/)(settings\.gradle(\.kts)?|build\.gradle(\.kts)?)$' | xargs -r -n1 dirname | sort -u | head -n1)"
          [ -n "$ROOT" ] || { echo "No Gradle settings/build file found"; exit 1; }
          echo "root=$ROOT" >> "$GITHUB_OUTPUT"

      - name: Align compile/target SDK if fallback used
        if: env.USING_API != '34'
        shell: bash
        run: |
          API="${USING_API}"
          ROOT="${{ steps.detect.outputs.root }}"
          sed -i "s/compileSdkVersion [0-9][0-9]*/compileSdkVersion ${API}/" "$ROOT/app/build.gradle" || true
          sed -i "s/targetSdkVersion [0-9][0-9]*/targetSdkVersion ${API}/" "$ROOT/app/build.gradle" || true

      - name: Install Gradle 8.4 via SDKMAN
        shell: bash
        run: |
          curl -s "https://get.sdkman.io" | bash
          source "$HOME/.sdkman/bin/sdkman-init.sh"
          sdk install gradle 8.4
          gradle --version

      - name: Build Debug APK
        shell: bash
        run: |
          set -euxo pipefail
          cd "${{ steps.detect.outputs.root }}"
          gradle assembleDebug --stacktrace --warning-mode all --info

      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: StealthCam-debug
          path: ${{ steps.detect.outputs.root }}/app/build/outputs/apk/debug/*.apk
YAML

mkdir -p .github/workflows
cat > .github/workflows/android.yml <<'YAML'
name: Android CI
on:
  push:
    branches: ["main"]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - name: Set up Android SDK
        uses: android-actions/setup-android@v3
        with:
          accept-android-sdk-licenses: true
          cmdline-tools-version: 11076708

      - name: Install SDK packages (with fallback)
        shell: bash
        run: |
          set -euxo pipefail
          sdkmanager --list || true
          sdkmanager "platform-tools" || true
          if ! sdkmanager "platforms;android-34"; then
            LATEST_PLATFORM="$(sdkmanager --list | sed -n 's/^[[:space:]]*\(platforms;android-[0-9]\+\).*/\1/p' | sort -V | tail -1)"
            sdkmanager "${LATEST_PLATFORM}"
            USING_API="${LATEST_PLATFORM##*android-}"
          else
            USING_API="34"
          fi
          if ! sdkmanager "build-tools;34.0.0"; then
            LATEST_BT="$(sdkmanager --list | sed -n 's/^[[:space:]]*\(build-tools;[0-9][0-9.]*\).*/\1/p' | sort -V | tail -1)"
            sdkmanager "${LATEST_BT}"
          fi
          echo "USING_API=${USING_API}" >> "$GITHUB_ENV"

      - name: Detect Gradle project root
        id: detect
        shell: bash
        run: |
          set -e
          ROOT="$(git ls-files | grep -E '(^|/)(settings\.gradle(\.kts)?|build\.gradle(\.kts)?)$' | xargs -r -n1 dirname | sort -u | head -n1)"
          [ -n "$ROOT" ] || { echo "No Gradle settings/build file found"; exit 1; }
          echo "root=$ROOT" >> "$GITHUB_OUTPUT"

      - name: Install Gradle 8.4 via SDKMAN
        shell: bash
        run: |
          curl -s "https://get.sdkman.io" | bash
          source "$HOME/.sdkman/bin/sdkman-init.sh"
          sdk install gradle 8.4
          gradle --version
          echo "$HOME/.sdkman/candidates/gradle/current/bin" >> "$GITHUB_PATH"

      - name: Build Debug APK
        shell: bash
        run: |
          set -euxo pipefail
          cd "${{ steps.detect.outputs.root }}"
          # important: re-sursăm SDKMAN ca 'gradle' să fie în PATH
          source "$HOME/.sdkman/bin/sdkman-init.sh"
          gradle assembleDebug --stacktrace --warning-mode all --info

      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: StealthCam-debug
          path: ${{ steps.detect.outputs.root }}/app/build/outputs/apk/debug/*.apk
YAML

git add .github/workflows/android.yml
git commit -m "CI: fix Gradle PATH + robust SDK install"
git push
git fetch origin
git pull --rebase origin main     # sau: git rebase origin/main
# dacă apar conflicte: editezi fișierele cu <<<<<<< ======= >>>>>>,
git add -A
git rebase --continue
git push -u origin main
# dacă nu ai gradle local, poți folosi temporar SDKMAN doar ca să generezi wrapperul:
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install gradle 8.4
gradle wrapper --gradle-version 8.4
git add gradlew gradlew.bat gradle/wrapper/
git commit -m "Add Gradle wrapper 8.4"
git push
cat > .github/workflows/android.yml <<'YAML'
name: Android CI
on:
  push:
    branches: ["main"]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"
      - name: Set up Android SDK
        uses: android-actions/setup-android@v3
        with:
          accept-android-sdk-licenses: true
          cmdline-tools-version: 11076708
      - name: Install SDK packages (with fallback)
        shell: bash
        run: |
          set -euxo pipefail
          sdkmanager "platform-tools" || true
          sdkmanager "platforms;android-34" || sdkmanager "platforms;android-35"
          sdkmanager "build-tools;34.0.0" || sdkmanager "build-tools;35.0.0" || true
      - name: Detect Gradle project root
        id: detect
        shell: bash
        run: |
          ROOT="$(git ls-files | grep -E '(^|/)(settings\.gradle(\.kts)?|build\.gradle(\.kts)?)$' | xargs -r -n1 dirname | sort -u | head -n1)"
          [ -n "$ROOT" ] || { echo "No Gradle settings/build file found"; exit 1; }
          echo "root=$ROOT" >> "$GITHUB_OUTPUT"
      - name: Make wrapper executable
        run: chmod +x "${{ steps.detect.outputs.root }}/gradlew" || true
      - name: Build Debug APK
        shell: bash
        run: |
          set -euxo pipefail
          cd "${{ steps.detect.outputs.root }}"
          ./gradlew assembleDebug --stacktrace --warning-mode all --info
      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: StealthCam-debug
          path: ${{ steps.detect.outputs.root }}/app/build/outputs/apk/debug/*.apk
YAML

git add .github/workflows/android.yml
git commit -m "CI: use Gradle wrapper"
git push
# Instalează temporar Gradle local doar ca să generezi wrapperul
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install gradle 8.4
# Generează wrapperul în repo
gradle wrapper --gradle-version 8.4
# Adaugă fișierele wrapper la git
git add gradlew gradlew.bat gradle/wrapper/
git commit -m "Add Gradle wrapper 8.4"
git push
mkdir -p .github/workflows
# deschide editorul tău și lipește exact YAML-ul de mai sus
git add .github/workflows/android.yml
git commit -m "CI: use Gradle wrapper + stable SDK install"
git push
name: Android CI
on:
jobs:
name: Android CI
on:
jobs:
mkdir -p .github/workflows
# deschide editorul tău și lipește exact YAML-ul de mai sus
git add .github/workflows/android.yml
git commit -m "CI: use Gradle wrapper + stable SDK install"
git push
name: Android CI
on:
jobs:
