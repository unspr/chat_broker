unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Menus, Unit2;

type

  { TForm1 }

  TForm1 = class(TForm)
    Memo1: TMemo;
    Edit1: TEdit;
    Button1: TButton;
    Button2: TButton;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private

  public

  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.Button1Click(Sender: TObject);
begin
  Memo1.Lines.Add('me: ' + Edit1.Text);
  Edit1.Clear; // Optional: clear the input after adding
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  if Form2 = nil then
    Form2 := TForm2.Create(Application);
  try
    Form2.ShowModal;
  finally
    Form2.Free;
    Form2 := nil;
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin

end;

end.

