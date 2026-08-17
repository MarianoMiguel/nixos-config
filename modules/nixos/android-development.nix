{ lib, pkgs, ... }:

let
  jdk = pkgs.jdk21;
  defaultAvdName = "Pixel_9_Pro_API_36";
  defaultAvdApi = "36";
  defaultAvdDevice = "pixel_9_pro";
  defaultNdkVersion = "29.0.14206865";

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    # API 36 is the 2026 Play target. API 35 provides compatibility coverage,
    # while API 37 catches the next platform's behavior and 16 KiB page-size
    # issues before release.
    platformVersions = [
      "35"
      "36"
      "37.0"
    ];
    buildToolsVersions = [
      "35.0.1"
      "36.0.0"
      "37.0.0"
    ];
    includeSources = true;

    includeEmulator = true;
    includeSystemImages = true;
    systemImageTypes = [ "google_apis_playstore" ];
    abiVersions = [ "x86_64" ];

    # Include both the broadly supported CMake/NDK generation and the current
    # generation so existing libraries and new JNI/native code build locally.
    includeCmake = true;
    cmakeVersions = [
      "3.22.1"
      "4.1.2"
    ];
    includeNDK = true;
    ndkVersions = [
      "28.2.13676358"
      defaultNdkVersion
    ];
  };

  androidSdk = androidComposition.androidsdk;
  androidHome = "${androidSdk}/libexec/android-sdk";

  # JetBrains' official Kotlin LSP gives VS Code and Neovim the same
  # IntelliJ-powered Kotlin analysis, including experimental Android Gradle
  # Plugin project support. Keep the platform-specific release pinned because
  # the upstream extension bundles its own language-server runtime.
  jetbrainsKotlinExtension = pkgs.vscode-utils.buildVscodeExtension {
    pname = "jetbrains-kotlin-server";
    version = "0.0.6";
    src = pkgs.fetchurl {
      url = "https://download-cdn.jetbrains.com/language-server/kotlin-server/262.9593.0/kotlin-server-0.0.6-linux-amd64.vsix";
      hash = "sha256-kJdM2B0x+ie1xIfCn3EqlWvGiHZn1XEsJgMD9+M2h+w=";
    };
    vscodeExtPublisher = "JetBrains";
    vscodeExtName = "kotlin-server";
    vscodeExtUniqueId = "JetBrains.kotlin-server";
  };

  kotlinLsp = pkgs.writeShellApplication {
    name = "kotlin-lsp";
    text = ''
      exec ${jetbrainsKotlinExtension}/share/vscode/extensions/JetBrains.kotlin-server/server/bin/intellij-server "$@"
    '';
  };

  androidVscode = pkgs.vscode-with-extensions.override {
    vscodeExtensions = [
      jetbrainsKotlinExtension
      pkgs.vscode-extensions.redhat.java
      pkgs.vscode-extensions.vscjava.vscode-gradle
      pkgs.vscode-extensions.vscjava.vscode-java-debug
      pkgs.vscode-extensions.vscjava.vscode-java-dependency
      pkgs.vscode-extensions.vscjava.vscode-java-test
    ];
  };

  androidAvdCreate = pkgs.writeShellApplication {
    name = "android-avd-create";
    runtimeInputs = [
      androidSdk
      jdk
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = ''
      export ANDROID_HOME=${lib.escapeShellArg androidHome}
      export ANDROID_SDK_ROOT="$ANDROID_HOME"
      export JAVA_HOME=${lib.escapeShellArg jdk.home}
      export ANDROID_USER_HOME="''${HOME:?HOME is not set}/.android"
      export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"

      avd_name="''${1:-${defaultAvdName}}"
      api="''${2:-${defaultAvdApi}}"
      device="''${3:-${defaultAvdDevice}}"
      avd_home="$ANDROID_AVD_HOME"

      case "$api" in
        35|36)
          image="system-images;android-$api;google_apis_playstore;x86_64"
          ;;
        37|37.0)
          image="system-images;android-37.0;google_apis_playstore_ps16k;x86_64"
          ;;
        *)
          echo "Unsupported API '$api'. Installed emulator APIs: 35, 36, and 37." >&2
          exit 2
          ;;
      esac

      if [ -d "$avd_home/$avd_name.avd" ]; then
        echo "Android virtual device '$avd_name' already exists."
        exit 0
      fi

      mkdir -p "$avd_home"
      printf 'no\n' | avdmanager create avd \
        --name "$avd_name" \
        --package "$image" \
        --device "$device"

      config_file="$avd_home/$avd_name.avd/config.ini"
      set_avd_option() {
        key="$1"
        value="$2"
        if grep -q "^$key=" "$config_file"; then
          sed -i "s/^$key=.*/$key=$value/" "$config_file"
        else
          printf '%s=%s\n' "$key" "$value" >> "$config_file"
        fi
      }

      # avdmanager currently disables this flag even for a Play Store image.
      # Keep the default AVD representative of a normal consumer phone and
      # make desktop keyboard input work without additional UI setup.
      set_avd_option PlayStore.enabled yes
      set_avd_option hw.keyboard yes

      echo "Created Android virtual device '$avd_name' for API $api."
    '';
  };

  androidEmulator = pkgs.writeShellApplication {
    name = "android-emulator";
    runtimeInputs = [
      androidAvdCreate
      androidSdk
      jdk
    ];
    text = ''
      export ANDROID_HOME=${lib.escapeShellArg androidHome}
      export ANDROID_SDK_ROOT="$ANDROID_HOME"
      export JAVA_HOME=${lib.escapeShellArg jdk.home}
      export ANDROID_USER_HOME="''${HOME:?HOME is not set}/.android"
      export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"

      avd_name="''${1:-${defaultAvdName}}"
      if [ "$#" -gt 0 ]; then
        shift
      fi

      avd_home="$ANDROID_AVD_HOME"
      if [ ! -d "$avd_home/$avd_name.avd" ]; then
        android-avd-create "$avd_name" ${lib.escapeShellArg defaultAvdApi} ${lib.escapeShellArg defaultAvdDevice}
      fi

      exec emulator -avd "$avd_name" -accel auto -gpu auto "$@"
    '';
  };

  androidDoctor = pkgs.writeShellApplication {
    name = "android-doctor";
    runtimeInputs = [
      androidSdk
      jdk
      pkgs.coreutils
    ];
    text = ''
      export ANDROID_HOME=${lib.escapeShellArg androidHome}
      export ANDROID_SDK_ROOT="$ANDROID_HOME"
      export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/${defaultNdkVersion}"
      export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
      export JAVA_HOME=${lib.escapeShellArg jdk.home}
      export ANDROID_USER_HOME="''${HOME:?HOME is not set}/.android"
      export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"

      status=0

      echo "Android SDK: $ANDROID_HOME"
      echo "Android NDK: $ANDROID_NDK_HOME"
      java -version
      adb version

      if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        echo "KVM device: usable"
      else
        echo "KVM device: unavailable to this user" >&2
        status=1
      fi

      if ! emulator -accel-check; then
        status=1
      fi

      echo "Configured virtual devices:"
      avdmanager list avd -c || status=1

      exit "$status"
    '';
  };
in
{
  # Building the declarative SDK means accepting Google's Android SDK terms.
  nixpkgs.config.android_sdk.accept_license = true;

  users.users.mariano.extraGroups = [ "kvm" ];

  environment.sessionVariables = {
    ANDROID_HOME = androidHome;
    ANDROID_SDK_ROOT = androidHome;
    ANDROID_NDK_HOME = "${androidHome}/ndk/${defaultNdkVersion}";
    ANDROID_NDK_ROOT = "${androidHome}/ndk/${defaultNdkVersion}";
    ANDROID_USER_HOME = "/home/mariano/.android";
    ANDROID_AVD_HOME = "/home/mariano/.android/avd";
    JAVA_HOME = jdk.home;
  };

  environment.systemPackages = [
    androidSdk
    pkgs.android-studio
    # This wins the executable collision with the base VS Code package already
    # in the workstation profile while retaining the user's normal VS Code
    # state and adding the Android-oriented extensions above.
    (lib.hiPrio androidVscode)
    jdk

    # Project wrappers should pin Gradle, but the global tool is useful for
    # bootstrapping and diagnostics outside an existing project.
    pkgs.gradle
    pkgs.kotlin
    kotlinLsp
    pkgs.jdt-language-server
    pkgs.ktlint
    pkgs.detekt
    pkgs.google-java-format

    # Native/JNI builds and release/device inspection.
    pkgs.cmake
    pkgs.ninja
    pkgs.bundletool
    pkgs.apktool
    pkgs.scrcpy
    pkgs.usbutils

    androidAvdCreate
    androidEmulator
    androidDoctor
  ];

  # Seed a production-like Pixel emulator without blocking system activation.
  # The AVD remains writable user state; its SDK and system image stay pinned by
  # this module.
  systemd.user.services.android-default-avd = {
    description = "Create the default Android development virtual device";
    wantedBy = [ "default.target" ];
    unitConfig = {
      ConditionUser = "mariano";
      ConditionPathExists = "!%h/.android/avd/${defaultAvdName}.avd";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${androidAvdCreate}/bin/android-avd-create";
    };
  };
}
