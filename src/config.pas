unit config;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Menus,
  ComCtrls, IniFiles;

type

  { TCfgForm }

  TCfgForm = class(TForm)
    SaveProxy: TButton;
    EditProxyHost: TEdit;
    EditProxyPort: TEdit;
    EditURL: TEdit;
    EditToken: TEdit;
    EditModel: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label5: TLabel;
    ButtonSave: TButton;
    Label3: TLabel;
    Label4: TLabel;
    PageControl1: TPageControl;
    GeminiConfigTab: TTabSheet;
    ProxyConfigTab: TTabSheet;
    procedure SaveProxyClick(Sender: TObject);
    procedure ButtonSaveClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    procedure LoadConfig;
    procedure SaveConfig;
  public

  end;

var
  CfgForm: TCfgForm;
  IniFileName: string;

implementation

{$R *.lfm}

{ TCfgForm }

procedure TCfgForm.FormCreate(Sender: TObject);
begin
end;

procedure TCfgForm.FormShow(Sender: TObject);
begin
  LoadConfig;
end;

procedure TCfgForm.LoadConfig;
var
  Ini: TIniFile;
begin
  IniFileName := ExtractFilePath(Application.ExeName) + 'config.ini';
  Ini := TIniFile.Create(IniFileName);

  try
    EditURL.Text := Ini.ReadString('AIConfig', 'URL', '');
    EditToken.Text := Ini.ReadString('AIConfig', 'Token', '');
    EditModel.Text := Ini.ReadString('AIConfig', 'Model', 'gemini-3.1-flash-lite');
    EditProxyHost.Text := Ini.ReadString('Proxy', 'Host', '');
    EditProxyPort.Text := Ini.ReadString('Proxy', 'Port', '');
  finally
    Ini.Free;
  end;
end;

procedure TCfgForm.SaveConfig;
var
  Ini: TIniFile;
begin
  IniFileName := ExtractFilePath(Application.ExeName) + 'config.ini';
  Ini := TIniFile.Create(IniFileName);

  try
    Ini.WriteString('AIConfig', 'URL', EditURL.Text);
    Ini.WriteString('AIConfig', 'Token', EditToken.Text);
    Ini.WriteString('AIConfig', 'Model', EditModel.Text);
  finally
    Ini.Free;
  end;
end;

procedure TCfgForm.ButtonSaveClick(Sender: TObject);
begin
  SaveConfig;
  ModalResult := mrOk;
end;

procedure TCfgForm.SaveProxyClick(Sender: TObject);
var
  Ini: TIniFile;
begin
  IniFileName := ExtractFilePath(Application.ExeName) + 'config.ini';
  Ini := TIniFile.Create(IniFileName);

  try
    Ini.WriteString('Proxy', 'Host', EditProxyHost.Text);
    Ini.WriteString('Proxy', 'Port', EditProxyPort.Text);
  finally
    Ini.Free;
  end;
end;

end.
