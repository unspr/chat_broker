unit Unit2;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, IniFiles;

type

  { TForm2 }

  TForm2 = class(TForm)
    Button1: TButton;
    EditURL: TEdit;
    EditHeaders: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    ButtonSave: TButton;
    ButtonCancel: TButton;
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
  a: string;

implementation

{$R *.lfm}

{ TForm2 }

procedure TForm2.FormCreate(Sender: TObject);
begin
  // LoadConfig will be called in FormShow to ensure UI elements are ready
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
    EditHeaders.Text := Ini.ReadString('AIConfig', 'Headers', '');
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
    Ini.WriteString('AIConfig', 'Headers', EditHeaders.Text);
  finally
    Ini.Free;
  end;
end;

procedure TForm2.ButtonSaveClick(Sender: TObject);
begin
  SaveConfig;
  ModalResult := mrOk; // Close the dialog with OK result
end;
end.
