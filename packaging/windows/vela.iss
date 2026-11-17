#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef AppVersionNumeric
  #error AppVersionNumeric is required
#endif
#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif

[Setup]
AppId={{829C9B0C-FB79-4CC7-B316-BC77A2A0F376}
AppName=Vela
AppVersion={#AppVersion}
VersionInfoVersion={#AppVersionNumeric}
AppPublisher=AbyssSkb and Vela contributors
AppPublisherURL=https://github.com/AbyssSkb/Vela
AppSupportURL=https://github.com/AbyssSkb/Vela/issues
DefaultDirName={localappdata}\Programs\Vela
DefaultGroupName=Vela
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Vela-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
UninstallDisplayIcon={app}\vela.exe
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
LicenseFile=..\..\LICENSE

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "..\..\rust_builder\cargokit\LICENSE"; DestDir: "{app}"; DestName: "Cargokit-LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Vela"; Filename: "{app}\vela.exe"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "Vela"; Flags: dontcreatekey uninsdeletevalue

[Run]
Filename: "{app}\vela.exe"; Description: "Launch Vela"; Flags: nowait postinstall
