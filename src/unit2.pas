unit Unit2;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, IniFiles;

type

  { TForm2 }

  TForm2 = class(TForm)
    EditURL: TEdit;
    EditToken: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    ButtonSave: TButton;
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
end.
