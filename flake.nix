{
  description = "A flake for libedgetpu";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, poetry2nix }:

    let
      overlay1 = final: prev: {
        flatbuffers = prev.flatbuffers.overrideAttrs (oldAttrs: {
          version = "24.5.26";
          NIX_CFLAGS_COMPILE = "-Wno-error=class-memaccess -Wno-error=maybe-uninitialized";
          cmakeFlags = oldAttrs.cmakeFlags or [ ] ++ [ "-DFLATBUFFERS_BUILD_SHAREDLIB=ON" ];
          NIX_CXXSTDLIB_COMPILE = "-std=c++17";
          configureFlags = oldAttrs.configureFlags or [ ] ++ [ "--enable-shared" ];
          doCheck = false;
          src = final.fetchFromGitHub {
            owner = "google";
            repo = "flatbuffers";
            rev = "v23.5.26";
            sha256 = "sha256-e+dNPNbCHYDXUS/W+hMqf/37fhVgEGzId6rhP3cToTE=";
          };
        });
      };

      overlay2 = final: prev: {
        abseil-cpp = prev.abseil-cpp.overrideAttrs (oldAttrs: {
          NIX_CXXSTDLIB_COMPILE = "-std=c++17";
          cmakeFlags = [
            "-DBUILD_SHARED_LIBS=ON"
            "-DBUILD_TESTING=OFF"
          ];
        });
      };
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ overlay1 overlay2 ];
      };

    in
    {

      packages.x86_64-linux.libedgetpu = with pkgs; stdenv.mkDerivation rec {
        pname = "libedgetpu";
        version = "master";

        src = fetchFromGitHub {
          owner = "google-coral";
          repo = pname;
          rev = "${version}";
          sha256 = "sha256-+8wV6w2uWp0yr/HRwgtSOUzkK++onHP1X5ctk+aWXjM=";
        };

        patches = [ ./libedgetpu-makefile.diff ];

        makeFlags = [ "-f" "makefile_build/Makefile" "libedgetpu"];

        buildInputs = [ libusb1 pkgs.abseil-cpp pkgs.flatbuffers ];

        nativeBuildInputs = [ xxd ];

        NIX_CXXSTDLIB_COMPILE = "-std=c++17";

        TFROOT = "${fetchFromGitHub {
          owner = "tensorflow";
          repo = "tensorflow";
          rev = "v2.15.0"; 
          sha256 = "sha256-tCFLEvJ1lHy7NcHDW9Dkd+2D60x+AvOB8EAwmUSQCtM=";
        }}";

        enableParallelBuilding = false;

        installPhase = ''
          mkdir -p $out/lib
          cp out/direct/k8/libedgetpu.so.1.0 $out/lib
          ln -s $out/lib/libedgetpu.so.1.0 $out/lib/libedgetpu.so.1
        '';
      };

      defaultPackage.x86_64-linux = self.packages.x86_64-linux.libedgetpu;

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ poetry2nix.overlay ];
          };

          poetryEnv = pkgs.poetry2nix.mkPoetryEnv {
            projectDir = ./.;
            python = pkgs.python310;
          };
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              poetry
              gcc
              stdenv.cc.cc.lib
            ];
          };
        });

    };
}

