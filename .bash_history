          name: gradle-build-log
          path: build.log
YAML

git add .github/workflows/android.yml
git commit -m "ci: autodetect :app, build, upload APK"
git pull --rebase --autostash origin main || true
git push
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 1
grep -RIl --include=build.gradle --include=build.gradle.kts "com.android.application" . || echo "NO_APP_MODULE"
# curățăm și punem structura minimă
rm -rf app
mkdir -p app/src/main/java/com/marius/stealthcam app/src/main/res/layout app/src/main/res/values
# settings.gradle
cat > settings.gradle <<'EOF'
rootProject.name = "StealthCam"
include(":app")
EOF

# build.gradle (top-level)
cat > build.gradle <<'EOF'
buildscript {
  repositories { google(); mavenCentral() }
  dependencies {
    classpath 'com.android.tools.build:gradle:8.2.2'
    classpath 'org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.22'
  }
}
allprojects { repositories { google(); mavenCentral() } }
EOF

# app/build.gradle (minimal, compatibil cu AGP 8.2.2)
cat > app/build.gradle <<'EOF'
plugins {
  id 'com.android.application'
  id 'org.jetbrains.kotlin.android'
}
android {
  namespace "com.marius.stealthcam"
  compileSdkVersion 34
  defaultConfig {
    applicationId "com.marius.stealthcam"
    minSdkVersion 26
    targetSdkVersion 34
    versionCode 1
    versionName "1.0"
  }
  buildTypes {
    release {
      minifyEnabled false
      proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
  }
  compileOptions { sourceCompatibility JavaVersion.VERSION_17; targetCompatibility JavaVersion.VERSION_17 }
  kotlinOptions  { jvmTarget = '17' }
}
dependencies {
  implementation 'androidx.appcompat:appcompat:1.6.1'
  implementation 'org.jetbrains.kotlin:kotlin-stdlib:1.9.22'
}
EOF

# Manifest + layout + Activity
cat > app/src/main/AndroidManifest.xml <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.marius.stealthcam">
  <application android:label="@string/app_name" android:theme="@style/Theme.AppCompat.DayNight.NoActionBar">
    <activity android:name=".MainActivity">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF

cat > app/src/main/res/values/strings.xml <<'EOF'
<resources><string name="app_name">StealthCam</string></resources>
EOF

cat > app/src/main/res/layout/activity_main.xml <<'EOF'
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent" android:layout_height="match_parent"
  android:gravity="center" android:orientation="vertical" android:padding="24dp">
  <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
    android:text="Hello StealthCam!" android:textSize="20sp"/>
</LinearLayout>
EOF

cat > app/src/main/java/com/marius/stealthcam/MainActivity.kt <<'EOF'
package com.marius.stealthcam
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
class MainActivity : AppCompatActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContentView(R.layout.activity_main)
  }
}
EOF

git add -A
git commit -m "feat: add minimal :app module (AGP 8.2.2, SDK 34)"
git pull --rebase --autostash origin main || true
git push --force-with-lease || git push
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
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: "17" }
      - uses: android-actions/setup-android@v3
        with: { accept-android-sdk-licenses: true }

      - name: Install SDK packages (prefer 34, fallback 35)
        shell: bash
        run: |
          set -euxo pipefail
          sdkmanager "platform-tools" || true
          sdkmanager "platforms;android-34" || sdkmanager "platforms;android-35" || true
          sdkmanager "build-tools;34.0.0"  || sdkmanager "build-tools;35.0.0"  || true

      - name: Use Gradle from runner (8.4)
        shell: bash
        run: |
          set -euxo pipefail
          v=8.4
          curl -L "https://services.gradle.org/distributions/gradle-${v}-bin.zip" -o gradle.zip
          unzip -q gradle.zip -d "$HOME/gradle"
          echo "$HOME/gradle/gradle-${v}/bin" >> "$GITHUB_PATH"
          gradle --version

      - name: Detect Android application module
        id: detect
        shell: bash
        run: |
          set -e
          HIT="$(grep -RIl --include=build.gradle --include=build.gradle.kts 'com.android.application' . | head -n1 || true)"
          [ -n "$HIT" ] || { echo "No module with 'com.android.application' found."; exit 1; }
          MOD_DIR="$(dirname "$HIT")"; MOD_REL="${MOD_DIR#./}"; MOD_NAME="${MOD_REL//\//:}"
          echo "module_dir=$MOD_REL"    >> "$GITHUB_OUTPUT"
          echo "module_path=:$MOD_NAME" >> "$GITHUB_OUTPUT"
          echo "Module: $MOD_REL | Gradle path ::$MOD_NAME"

      - name: Build Debug APK (capture logs)
        shell: bash
        run: |
          set -euxo pipefail
          ( gradle "${{ steps.detect.outputs.module_path }}:checkDebugAarMetadata" --stacktrace --console=plain --info || true ) | tee build.log
          ( gradle "${{ steps.detect.outputs.module_path }}:assembleDebug"         --stacktrace --console=plain --info || true ) | tee -a build.log

      - name: List outputs (debug)
        if: always()
        shell: bash
        run: |
          set -euxo pipefail
          echo "=== SEARCH APK/AAB ==="
          find . -maxdepth 9 -type f \( -name '*.apk' -o -name '*.aab' \) -print | sed 's/^/FOUND: /' || true
          echo "=== MODULE BUILD DIR ==="
          [ -d "${{ steps.detect.outputs.module_dir }}/build" ] && find "${{ steps.detect.outputs.module_dir }}/build" -maxdepth 6 -type f -print | sed 's/^/BUILDFILE: /' || echo "No module build dir."

      - name: Upload APK/AAB (always)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: build-artifacts
          path: |
            ${{ steps.detect.outputs.module_dir }}/build/outputs/apk/**/*.apk
            ${{ steps.detect.outputs.module_dir }}/build/outputs/bundle/**/*.aab
          if-no-files-found: warn

      - name: Upload build log (always)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: gradle-build-log
          path: build.log
YAML

git add .github/workflows/android.yml
git commit -m "ci: autodetect app module, build, upload APK"
git pull --rebase --autostash origin main || true
git push
# 1) Înlocuiește workflow-ul cu o variantă care EXTRAGE eroarea din log
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

      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: "17" }

      - uses: android-actions/setup-android@v3
        with: { accept-android-sdk-licenses: true }

      - name: Install SDK (API 34 pref, 35 fallback)
        shell: bash
        run: |
          set -euxo pipefail
          sdkmanager "platform-tools" || true
          sdkmanager "platforms;android-34" || sdkmanager "platforms;android-35" || true
          sdkmanager "build-tools;34.0.0"  || sdkmanager "build-tools;35.0.0"  || true

      - name: Install Gradle 8.4
        shell: bash
        run: |
          set -euxo pipefail
          v=8.4
          curl -L "https://services.gradle.org/distributions/gradle-${v}-bin.zip" -o gradle.zip
          unzip -q gradle.zip -d "$HOME/gradle"
          echo "$HOME/gradle/gradle-${v}/bin" >> "$GITHUB_PATH"
          gradle --version

      - name: Detect :app module
        id: detect
        shell: bash
        run: |
          set -e
          HIT="$(grep -RIl --include=build.gradle --include=build.gradle.kts 'com.android.application' . | head -n1 || true)"
          [ -n "$HIT" ] || { echo "No module with 'com.android.application' found."; exit 1; }
          MOD_DIR="$(dirname "$HIT")"; MOD_REL="${MOD_DIR#./}"; MOD_NAME="${MOD_REL//\//:}"
          echo "module_dir=$MOD_REL"    >> "$GITHUB_OUTPUT"
          echo "module_path=:$MOD_NAME" >> "$GITHUB_OUTPUT"
          echo "Module: $MOD_REL | Gradle path ::$MOD_NAME"

      - name: Build (capture FULL logs)
        shell: bash
        run: |
          set -euxo pipefail
          export GRADLE_OPTS="-Dorg.gradle.console=plain -Dorg.gradle.logging.stacktrace=all"
          ( gradle "${{ steps.detect.outputs.module_path }}:checkDebugAarMetadata" --stacktrace --info --no-daemon --rerun-tasks || true ) | tee build.log
          ( gradle "${{ steps.detect.outputs.module_path }}:assembleDebug"         --stacktrace --info --no-daemon --rerun-tasks || true ) | tee -a build.log
          echo "------ TAIL(build.log) ------"; tail -n 400 build.log || true
          echo "------ EXTRACT: What went wrong ------"
          awk 'f;/^\* What went wrong:/{f=1} /^\* Try:/{exit}' build.log || true
          echo "------ EXTRACT: A failure occurred while executing ------"
          grep -n "A failure occurred while executing" -n build.log || true

      - name: List outputs
        if: always()
        shell: bash
        run: |
          set -euxo pipefail
          find . -maxdepth 9 -type f \( -name '*.apk' -o -name '*.aab' \) -print | sed 's/^/FOUND: /' || true
          [ -d "${{ steps.detect.outputs.module_dir }}/build" ] && find "${{ steps.detect.outputs.module_dir }}/build" -maxdepth 6 -type f -print | sed 's/^/BUILDFILE: /' || echo "No module build dir."

      - name: Upload APK/AAB (always)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: build-artifacts
          path: |
            ${{ steps.detect.outputs.module_dir }}/build/outputs/apk/**/*.apk
            ${{ steps.detect.outputs.module_dir }}/build/outputs/bundle/**/*.aab
          if-no-files-found: warn

      - name: Upload build.log (always)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: gradle-build-log
          path: build.log
YAML

# 2) Commit + push
git add .github/workflows/android.yml
git commit -m "ci: force error extraction from Gradle log"
git pull --rebase --autostash origin main || true
git push
set -euxo pipefail
# 0) Verifică că ești într-un repo git
git rev-parse --is-inside-work-tree >/dev/null
# 1) .gitignore sănătos (să nu împingi fișiere mari)
cat > .gitignore <<'EOF'
# Gradle build
.gradle/
**/build/

# Local SDK / IDE
local.properties
.idea/
*.iml

# Distribuții Gradle/zip mari - NU în repo
gradle/
gradle.zip
*.zip

# Output-uri
*.apk
*.aab
EOF

# 2) settings.gradle (proiect + include modulul :app)
cat > settings.gradle <<'EOF'
rootProject.name = "StealthCam"
include(":app")
EOF

# 3) build.gradle top-level (AGP 8.2.2 + Kotlin 1.9.22)
cat > build.gradle <<'EOF'
buildscript {
  repositories { google(); mavenCentral() }
  dependencies {
    classpath 'com.android.tools.build:gradle:8.2.2'
    classpath 'org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.22'
  }
}
allprojects { repositories { google(); mavenCentral() } }
EOF

# 4) Structura minimă a modulului :app
rm -rf app
mkdir -p app/src/main/java/com/marius/stealthcam app/src/main/res/layout app/src/main/res/values
# 5) app/build.gradle (aplicația com.marius.stealthcam, compatibilă cu SDK 34)
cat > app/build.gradle <<'EOF'
plugins {
  id 'com.android.application'
  id 'org.jetbrains.kotlin.android'
}
android {
  namespace "com.marius.stealthcam"
  compileSdkVersion 34
  defaultConfig {
    applicationId "com.marius.stealthcam"
    minSdkVersion 26
    targetSdkVersion 34
    versionCode 1
    versionName "1.0"
  }
  buildTypes {
    release {
      minifyEnabled false
      proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
  }
  compileOptions { sourceCompatibility JavaVersion.VERSION_17; targetCompatibility JavaVersion.VERSION_17 }
  kotlinOptions  { jvmTarget = '17' }
}
dependencies {
  implementation 'androidx.appcompat:appcompat:1.6.1'
  implementation 'org.jetbrains.kotlin:kotlin-stdlib:1.9.22'
}
EOF

# 6) Manifest + res + Activity minimă
cat > app/src/main/AndroidManifest.xml <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.marius.stealthcam">
  <application android:label="@string/app_name" android:theme="@style/Theme.AppCompat.DayNight.NoActionBar">
    <activity android:name=".MainActivity">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF

cat > app/src/main/res/values/strings.xml <<'EOF'
<resources><string name="app_name">StealthCam</string></resources>
EOF

cat > app/src/main/res/layout/activity_main.xml <<'EOF'
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent" android:layout_height="match_parent"
  android:gravity="center" android:orientation="vertical" android:padding="24dp">
  <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
    android:text="Hello StealthCam!" android:textSize="20sp"/>
</LinearLayout>
EOF

cat > app/src/main/java/com/marius/stealthcam/MainActivity.kt <<'EOF'
package com.marius.stealthcam
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
class MainActivity : AppCompatActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContentView(R.layout.activity_main)
  }
}
EOF

# 7) Workflow GitHub Actions — auto-detect modulul de aplicație, build + upload APK
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

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - uses: android-actions/setup-android@v3
        with:
          accept-android-sdk-licenses: true

      - name: Install SDK packages (prefer 34, fallback 35)
        shell: bash
        run: |
          set -euxo pipefail
          sdkmanager "platform-tools" || true
          sdkmanager "platforms;android-34" || sdkmanager "platforms;android-35" || true
          sdkmanager "build-tools;34.0.0"  || sdkmanager "build-tools;35.0.0"  || true

      - name: Install Gradle 8.4 (runner-local)
        shell: bash
        run: |
          set -euxo pipefail
          v=8.4
          curl -L "https://services.gradle.org/distributions/gradle-${v}-bin.zip" -o gradle.zip
          unzip -q gradle.zip -d "$HOME/gradle"
          echo "$HOME/gradle/gradle-${v}/bin" >> "$GITHUB_PATH"
          gradle --version

      - name: Detect Android application module
        id: detect
        shell: bash
        run: |
          set -e
          HIT="$(grep -RIl --include=build.gradle --include=build.gradle.kts 'com.android.application' . | head -n1 || true)"
          [ -n "$HIT" ] || { echo "No module with 'com.android.application' found."; exit 1; }
          MOD_DIR="$(dirname "$HIT")"; MOD_REL="${MOD_DIR#./}"; MOD_NAME="${MOD_REL//\//:}"
          echo "module_dir=$MOD_REL"    >> "$GITHUB_OUTPUT"
          echo "module_path=:$MOD_NAME" >> "$GITHUB_OUTPUT"
          echo "Module: $MOD_REL | Gradle path ::$MOD_NAME"

      - name: Build Debug APK (capture logs)
        shell: bash
        run: |
          set -euxo pipefail
          ( gradle "${{ steps.detect.outputs.module_path }}:checkDebugAarMetadata" --stacktrace --console=plain --info || true ) | tee build.log
          ( gradle "${{ steps.detect.outputs.module_path }}:assembleDebug"         --stacktrace --console=plain --info || true ) | tee -a build.log

      - name: List outputs (debug)
        if: always()
        shell: bash
        run: |
          set -euxo pipefail
          echo "=== SEARCH APK/AAB ==="
          find . -maxdepth 9 -type f \( -name '*.apk' -o -name '*.aab' \) -print | sed 's/^/FOUND: /' || true
          echo "=== MODULE BUILD DIR ==="
          [ -d "${{ steps.detect.outputs.module_dir }}/build" ] && find "${{ steps.detect.outputs.module_dir }}/build" -maxdepth 6 -type f -print | sed 's/^/BUILDFILE: /' || echo "No module build dir."

      - name: Upload APK/AAB (always)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: build-artifacts
          path: |
            ${{ steps.detect.outputs.module_dir }}/build/outputs/apk/**/*.apk
            ${{ steps.detect.outputs.module_dir }}/build/outputs/bundle/**/*.aab
          if-no-files-found: warn

      - name: Upload build log (always)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: gradle-build-log
          path: build.log
YAML

# 8) Curățenie: nu vrem fișiere mari adăugate din greșeală
rm -f gradle.zip || true
rm -rf gradle/gradle-* || true
# 9) Commit & push (cu rebase/autostash ca să eviți conflicte)
git add -A
git commit -m "feat: minimal :app (com.marius.stealthcam) + Android CI (autodetect & upload APK)"
git pull --rebase --autostash origin main || true
git push
- name: Build Debug APK (strict + logs)
