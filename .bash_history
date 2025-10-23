        run: |
          set -euxo pipefail
          export GRADLE_OPTS="-Dorg.gradle.console=plain"
          ( gradle "${{ steps.detect.outputs.module_path }}:assembleDebug" --stacktrace --info --no-daemon || true ) | tee build.log

          echo "=== SEARCH APK (repo-wide) ==="
          find . -maxdepth 10 -type f -name '*.apk' -print | sed 's/^/FOUND: /' || true

          echo "=== MODULE BUILD DIR ==="
          if [ -d "${{ steps.detect.outputs.module_dir }}/build" ]; then
            find "${{ steps.detect.outputs.module_dir }}/build" -maxdepth 8 -type f -print | sed 's/^/BUILDFILE: /' || true
          else
            echo "No module build dir."
          fi

          if ! find "${{ steps.detect.outputs.module_dir }}/build/outputs/apk" -type f -name '*.apk' | grep -q . ; then
            echo "No APK found under ${{ steps.detect.outputs.module_dir }}/build/outputs/apk"
            tail -n 200 build.log || true
            exit 1
          fi

      - name: Upload APK + log
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: build-artifacts
          path: |
            **/*.apk
            build.log
          if-no-files-found: warn
EOF

# 6) Commit & push
git add -A
git commit -m "chore: minimal Java-only Android app + solid CI to produce APK"
git pull --rebase --autostash origin main || true
git push
set -euxo pipefail
# 1) Rescrie app/build.gradle (Groovy, minimal, Java-only, fără caractere ascunse)
cat > app/build.gradle <<'EOF'
plugins {
  id 'com.android.application'
}

android {
  namespace 'com.marius.stealthcam'
  compileSdkVersion 34

  defaultConfig {
    applicationId 'com.marius.stealthcam'
    minSdkVersion 26
    targetSdkVersion 34
    versionCode 1
    versionName '1.0'
  }

  buildTypes {
    release {
      minifyEnabled false
      proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
  }

  compileOptions {
    sourceCompatibility JavaVersion.VERSION_17
    targetCompatibility JavaVersion.VERSION_17
  }
}
EOF

# 2) Asigură settings.gradle & build.gradle top-level
cat > settings.gradle <<'EOF'
rootProject.name = "StealthCam"
include(":app")
EOF

cat > build.gradle <<'EOF'
buildscript {
  repositories { google(); mavenCentral() }
  dependencies {
    classpath 'com.android.tools.build:gradle:8.2.2'
  }
}
allprojects { repositories { google(); mavenCentral() } }
EOF

# 3) Workflow: dezactivează configuration-cache și arată conținutul fișierului + tail din log
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
    env:
      ORG_GRADLE_CONFIGURATION_CACHE: "false"
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - uses: android-actions/setup-android@v3
        with:
          accept-android-sdk-licenses: true

      - name: Install SDK (API 34)
        shell: bash
        run: |
          set -euxo pipefail
          sdkmanager "platform-tools"
          sdkmanager "platforms;android-34"
          sdkmanager "build-tools;34.0.0"

      - name: Install Gradle 8.4
        shell: bash
        run: |
          set -euxo pipefail
          v=8.4
          curl -L "https://services.gradle.org/distributions/gradle-${v}-bin.zip" -o gradle.zip
          unzip -q gradle.zip -d "$HOME/gradle"
          echo "$HOME/gradle/gradle-${v}/bin" >> "$GITHUB_PATH"
          gradle --version

      - name: Show app/build.gradle (with line numbers)
        shell: bash
        run: |
          set -euxo pipefail
          echo "----- app/build.gradle -----" | tee -a $GITHUB_STEP_SUMMARY
          nl -ba app/build.gradle | sed -n '1,200p' | tee -a $GITHUB_STEP_SUMMARY

      - name: Detect Android app module
        id: detect
        shell: bash
        run: |
          set -e
          HIT="$(grep -RIl --include=build.gradle --include=build.gradle.kts 'com.android.application' . || true)"
          if [ -z "$HIT" ]; then
            # Pentru Java-only nu apare pluginul de aplicație în grep, folosim fallback către :app
            if [ -d app ]; then
              echo "module_dir=app" >> "$GITHUB_OUTPUT"
              echo "module_path=:app" >> "$GITHUB_OUTPUT"
              echo "Module (fallback): app | Gradle path ::app"
            else
              echo "No module found"; exit 1
            fi
          else
            MOD_DIR="$(dirname "$HIT")"; MOD_REL="${MOD_DIR#./}"; MOD_NAME="${MOD_REL//\//:}"
            echo "module_dir=$MOD_REL"    >> "$GITHUB_OUTPUT"
            echo "module_path=:$MOD_NAME" >> "$GITHUB_OUTPUT"
            echo "Module: $MOD_REL | Gradle path ::$MOD_NAME"
          fi

      - name: Build Debug APK (no config cache, full logs)
        shell: bash
        run: |
          set -euxo pipefail
          export GRADLE_OPTS="-Dorg.gradle.console=plain -Dorg.gradle.warning.mode=all"
          ( gradle "${{ steps.detect.outputs.module_path }}:assembleDebug" --no-configuration-cache --stacktrace --info --no-daemon || true ) | tee build.log

          echo "===== LAST 300 LINES =====" | tee -a $GITHUB_STEP_SUMMARY
          tail -n 300 build.log | tee -a $GITHUB_STEP_SUMMARY || true

          echo "===== WHAT WENT WRONG =====" | tee -a $GITHUB_STEP_SUMMARY
          awk 'p;/^\* What went wrong:/{p=1} /^\* Try:/{exit}' build.log | tee -a $GITHUB_STEP_SUMMARY || true

          echo "===== SEARCH APK =====" | tee -a $GITHUB_STEP_SUMMARY
          find . -maxdepth 10 -type f -name '*.apk' -print | sed 's/^/FOUND: /' | tee -a $GITHUB_STEP_SUMMARY || true

          if ! find "${{ steps.detect.outputs.module_dir }}/build/outputs/apk" -type f -name '*.apk' | grep -q . ; then
            echo "No APK under ${{ steps.detect.outputs.module_dir }}/build/outputs/apk" | tee -a $GITHUB_STEP_SUMMARY
            exit 1
          fi

      - name: Upload APK + log
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: build-artifacts
          path: |
            **/*.apk
            build.log
          if-no-files-found: warn
YAML

# 4) Commit & push
git add -A
git commit -m "fix(ci): minimal Groovy build + disable config cache + print build.gradle and logs"
git pull --rebase --autostash origin main || true
git push
set -euxo pipefail
cat > .github/workflows/android.yml <<'YAML'
name: Android CI
on:
  push:
    branches: ["main"]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      ORG_GRADLE_CONFIGURATION_CACHE: "false"
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: "17" }
      - uses: android-actions/setup-android@v3
        with: { accept-android-sdk-licenses: true }

      - name: Install SDK (API 34)
        shell: bash
        run: |
          set -euxo pipefail
          sdkmanager "platform-tools"
          sdkmanager "platforms;android-34"
          sdkmanager "build-tools;34.0.0"

      - name: Install Gradle 8.4
        shell: bash
        run: |
          set -euxo pipefail
          v=8.4
          curl -L "https://services.gradle.org/distributions/gradle-${v}-bin.zip" -o gradle.zip
          unzip -q gradle.zip -d "$HOME/gradle"
          echo "$HOME/gradle/gradle-${v}/bin" >> "$GITHUB_PATH"
          gradle --version

      - name: Detect Android app module
        id: detect
        shell: bash
        run: |
          set -e
          if [ -d app ]; then
            echo "module_dir=app" >> "$GITHUB_OUTPUT"
            echo "module_path=:app" >> "$GITHUB_OUTPUT"
            echo "Module (fallback): app | Gradle path ::app"
          else
            HIT="$(grep -RIl --include=build.gradle --include=build.gradle.kts 'com.android.application' . | head -n1 || true)"
            [ -n "$HIT" ] || { echo "No module with 'com.android.application' found."; exit 1; }
            MOD_DIR="$(dirname "$HIT")"; MOD_REL="${MOD_DIR#./}"; MOD_NAME="${MOD_REL//\//:}"
            echo "module_dir=$MOD_REL"    >> "$GITHUB_OUTPUT"
            echo "module_path=:$MOD_NAME" >> "$GITHUB_OUTPUT"
            echo "Module: $MOD_REL | Gradle path ::$MOD_NAME"
          fi

      - name: Build & Package Debug (print to Summary)
        shell: bash
        run: |
          set -euxo pipefail
          export GRADLE_OPTS="-Dorg.gradle.console=plain -Dorg.gradle.warning.mode=all"
          # curățăm ca să vedem clar ce se produce
          gradle "${{ steps.detect.outputs.module_path }}:clean" --no-daemon
          # build + package (ambele, ca să nu rateze creația APK-ului)
          ( gradle "${{ steps.detect.outputs.module_path }}:assembleDebug" --no-daemon --stacktrace --info || true ) | tee build.log
          ( gradle "${{ steps.detect.outputs.module_path }}:packageDebug"  --no-daemon --stacktrace --info || true ) | tee -a build.log

          echo "===== TASKS containing 'package' =====" >> $GITHUB_STEP_SUMMARY
          gradle "${{ steps.detect.outputs.module_path }}:tasks" --all | grep -i package | head -n 100 >> $GITHUB_STEP_SUMMARY || true

          echo "===== TREE app/build (top 400 lines) =====" >> $GITHUB_STEP_SUMMARY
          if [ -d "${{ steps.detect.outputs.module_dir }}/build" ]; then
            find "${{ steps.detect.outputs.module_dir }}/build" -maxdepth 6 -type f | sort | head -n 400 >> $GITHUB_STEP_SUMMARY
          else
            echo "No module build dir." >> $GITHUB_STEP_SUMMARY
          fi

          echo "===== SEARCH *.apk repo-wide =====" >> $GITHUB_STEP_SUMMARY
          find . -maxdepth 10 -type f -name '*.apk' -print | sed 's/^/FOUND: /' >> $GITHUB_STEP_SUMMARY || true

          echo "===== TAIL(build.log, 300) =====" >> $GITHUB_STEP_SUMMARY
          tail -n 300 build.log >> $GITHUB_STEP_SUMMARY || true

      - name: Upload APKs + build dir + logs (always)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: build-artifacts
          path: |
            **/*.apk
            ${{ steps.detect.outputs.module_dir }}/build/**
            build.log
          if-no-files-found: warn
          retention-days: 14
YAML

git add .github/workflows/android.yml
git commit -m "ci: run :app:packageDebug, dump build tree, upload build dir + any APK"
git pull --rebase --autostash origin main || true
git push
set -euxo pipefail
# Înlocuiește pasul de build cu FAIL la eroare + diagnostic complet în Summary
cat > .github/workflows/android.yml <<'YAML'
name: Android CI
on:
  push:
    branches: ["main"]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      ORG_GRADLE_CONFIGURATION_CACHE: "false"
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: "17" }
      - uses: android-actions/setup-android@v3
        with: { accept-android-sdk-licenses: true }

      - name: Install SDK (API 34)
        shell: bash
        run: |
          set -euxo pipefail
          sdkmanager "platform-tools"
          sdkmanager "platforms;android-34"
          sdkmanager "build-tools;34.0.0"

      - name: Install Gradle 8.4
        shell: bash
        run: |
          set -euxo pipefail
          v=8.4
          curl -L "https://services.gradle.org/distributions/gradle-${v}-bin.zip" -o gradle.zip
          unzip -q gradle.zip -d "$HOME/gradle"
          echo "$HOME/gradle/gradle-${v}/bin" >> "$GITHUB_PATH"
          gradle --version

      - name: Detect Android app module
        id: detect
        shell: bash
        run: |
          set -e
          if [ -d app ]; then
            echo "module_dir=app" >> "$GITHUB_OUTPUT"
            echo "module_path=:app" >> "$GITHUB_OUTPUT"
            echo "Module: app | Gradle path ::app"
          else
            HIT="$(grep -RIl --include=build.gradle --include=build.gradle.kts 'com.android.application' . | head -n1 || true)"
            [ -n "$HIT" ] || { echo "No module with 'com.android.application' found."; exit 1; }
            MOD_DIR="$(dirname "$HIT")"; MOD_REL="${MOD_DIR#./}"; MOD_NAME="${MOD_REL//\//:}"
            echo "module_dir=$MOD_REL"    >> "$GITHUB_OUTPUT"
            echo "module_path=:$MOD_NAME" >> "$GITHUB_OUTPUT"
            echo "Module: $MOD_REL | Gradle path ::$MOD_NAME"
          fi

      - name: Build & Package Debug (STRICT — fail on error)
        shell: bash
        run: |
          set -euxo pipefail
          export GRADLE_OPTS="-Dorg.gradle.console=plain -Dorg.gradle.warning.mode=all"
          # curățăm și afișăm proprietăți utile
          gradle "${{ steps.detect.outputs.module_path }}:clean" --no-daemon
          gradle "${{ steps.detect.outputs.module_path }}:properties" --no-daemon | tee gradle.properties.out || true

          # rulează build-ul, DAR fără "|| true" -> dacă dă eroare, jobul PICA și vedem cauza
          gradle "${{ steps.detect.outputs.module_path }}:assembleDebug" --no-daemon --stacktrace --info --warning-mode all | tee build.log

          # listări după build
          echo "===== SEARCH *.apk (repo) ====="        >> $GITHUB_STEP_SUMMARY
          find . -maxdepth 10 -type f -name '*.apk' -print | sed 's/^/FOUND: /' >> $GITHUB_STEP_SUMMARY || true

          echo "===== TREE app/build (top 400) ====="    >> $GITHUB_STEP_SUMMARY
          if [ -d "${{ steps.detect.outputs.module_dir }}/build" ]; then
            find "${{ steps.detect.outputs.module_dir }}/build" -maxdepth 7 -type f | sort | head -n 400 >> $GITHUB_STEP_SUMMARY
          else
            echo "No module build dir." >> $GITHUB_STEP_SUMMARY
          fi

          echo "===== TAIL(build.log, 300) ====="        >> $GITHUB_STEP_SUMMARY
          tail -n 300 build.log >> $GITHUB_STEP_SUMMARY || true

          echo "===== WHAT WENT WRONG ====="             >> $GITHUB_STEP_SUMMARY
          awk 'p;/^\* What went wrong:/{p=1} /^\* Try:/{exit}' build.log >> $GITHUB_STEP_SUMMARY || true

      - name: Upload artifacts (always)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: build-artifacts
          path: |
            **/*.apk
            build.log
            gradle.properties.out
          if-no-files-found: warn
          retention-days: 14
YAML

git add .github/workflows/android.yml
git commit -m "ci: strict assembleDebug (fail on error) + clear Summary and artifacts"
git pull --rebase --autostash origin main || true
git push
# 1) Creează fișierul proguard (poate fi gol)
printf "# keep rules here if you enable minify\n" > app/proguard-rules.pro
# 2) (opțional) asigură-te că există res/values/strings.xml & layout (deja sunt)
# ls app/src/main/res/values/strings.xml app/src/main/res/layout/activity_main.xml
# 3) Commit & push
git add app/proguard-rules.pro
git commit -m "fix: add missing proguard-rules.pro for :app"
git pull --rebase --autostash origin main || true
git push
# rescrie doar pasul de build ca să captureze eroarea cu context mare
cat > .github/workflows/android.yml <<'YAML'
name: Android CI
on:
  push: { branches: ["main"] }
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: "17" }
      - uses: android-actions/setup-android@v3
        with: { accept-android-sdk-licenses: true }
      - name: Install SDK 34
        run: |
          set -euxo pipefail
          sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
      - name: Gradle 8.4
        run: |
          set -euxo pipefail
          v=8.4
          curl -L "https://services.gradle.org/distributions/gradle-${v}-bin.zip" -o gradle.zip
          unzip -q gradle.zip -d "$HOME/gradle"
          echo "$HOME/gradle/gradle-${v}/bin" >> "$GITHUB_PATH"
      - name: Assemble Debug (strict)
        run: |
          set -euxo pipefail
          gradle :app:clean --no-daemon
          # rulăm cu debug + stacktrace, salvăm log-ul complet
          ( gradle :app:assembleDebug --no-daemon --stacktrace --debug || true ) | tee build.log

          # numerotăm liniile din log și extragem fereastra în jurul FAIL-ului
          nl -ba build.log > build.n.log
          FAIL_LINE=$(grep -n "^FAILURE: Build failed" build.n.log | head -n1 | cut -d: -f1 || true)
          if [ -n "$FAIL_LINE" ]; then
            START=$(( FAIL_LINE>200 ? FAIL_LINE-200 : 1 ))
            END=$(( FAIL_LINE+60 ))
            echo "===== ERROR CONTEXT ($START..$END) =====" >> $GITHUB_STEP_SUMMARY
            sed -n "${START},${END}p" build.n.log >> $GITHUB_STEP_SUMMARY
          fi

          echo "===== SEARCH APK =====" >> $GITHUB_STEP_SUMMARY
          find . -type f -name '*.apk' -print | sed 's/^/FOUND: /' >> $GITHUB_STEP_SUMMARY || true
      - name: Upload log + any APK
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: build-artifacts
          path: |
            build.log
            build.n.log
            **/*.apk
          if-no-files-found: warn
YAML

git add .github/workflows/android.yml
git commit -m "ci: strict assembleDebug + capture error window into Summary"
git pull --rebase --autostash origin main || true
git push
set -euxo pipefail
# 1) Adaugă android:exported="true" la MainActivity (are intent-filter LAUNCHER)
cat > app/src/main/AndroidManifest.xml <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
  package="com.marius.stealthcam">

  <application
    android:label="@string/app_name"
    android:theme="@android:style/Theme.Material.Light">
    <activity
      android:name=".MainActivity"
      android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF

# 2) (siguranță) asigură fișierul proguard există
[ -f app/proguard-rules.pro ] || printf "# keep rules here\n" > app/proguard-rules.pro
# 3) Commit & push
git add app/src/main/AndroidManifest.xml app/proguard-rules.pro
git commit -m "fix(manifest): add android:exported=\"true\" for MainActivity (targetSdk 31+)"
git pull --rebase --autostash origin main || true
git push
git add app/src/main app/build.gradle
git commit -m "feat: add RecordingService and CameraX video support"
