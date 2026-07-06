unit Unit2;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Menus,
  ComCtrls, IniFiles;

type

  { TForm2 }

  TForm2 = class(TForm)
    SaveProxy: TButton;
    EditProxyHost: TEdit;
    EditProxyPort: TEdit;
    EditURL: TEdit;
    EditToken: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    ButtonSave: TButton;
    Label3: TLabel;
    Label4: TLabel;
    PageControl1: TPageControl;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
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
  Form2: TForm2;
  IniFileName: string;

implementation

{$R *.lfm}

{ TForm2 }

procedure TForm2.FormCreate(Sender: TObject);
begin
end;

procedure TForm2.FormShow(Sender: TObject);
begin
  LoadConfig;
end;

procedure TForm2.LoadConfig;
var
  Ini: TIniFile;
begin
  IniFileName := ExtractFilePath(Application.ExeName) + 'config.ini';
  Ini := TIniFile.Create(IniFileName);

  try
    EditURL.Text := Ini.ReadString('AIConfig', 'URL', '');
    EditToken.Text := Ini.ReadString('AIConfig', 'Token', '');
    EditProxyHost.Text := Ini.ReadString('Proxy', 'Host', '');
    EditProxyPort.Text := Ini.ReadString('Proxy', 'Port', '');
  finally
    Ini.Free;
  end;
end;

procedure TForm2.SaveConfig;
var
  Ini: TIniFile;
begin
  IniFileName := ExtractFilePath(Application.ExeName) + 'config.ini';
  Ini := TIniFile.Create(IniFileName);

  try
    Ini.WriteString('AIConfig', 'URL', EditURL.Text);
    Ini.WriteString('AIConfig', 'Token', EditToken.Text);
  finally
    Ini.Free;
  end;
end;

procedure TForm2.ButtonSaveClick(Sender: TObject);
begin
  SaveConfig;
  ModalResult := mrOk;
end;

procedure TForm2.SaveProxyClick(Sender: TObject);
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
