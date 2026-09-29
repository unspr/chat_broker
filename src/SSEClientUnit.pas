unit SSEClientUnit;

{$DEFINE USE_UNIX_SOCKETS}
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, LazLogger, process, sockets, fpjson, jsonparser;

type

  TSSEEvent = record
    Data: string;
  end;


  TOnSSEEvent = procedure(Sender: TObject; const AEvent: TSSEEvent) of object;
  TOnSSEOpen = procedure(Sender: TObject) of object;
  TOnSSEClose = procedure(Sender: TObject) of object;
  TOnSSEError = procedure(Sender: TObject; const AError: string) of object;

  TSSEClientThread = class(TThread)
  private
    FPreviousInteractionID: string;
    FPrompt: string;
    FNewInteractionID: string; // To store the new interaction ID from server
    FOnEvent: TOnSSEEvent;
    FOnOpen: TOnSSEOpen;
    FOnClose: TOnSSEClose;
    FOnError: TOnSSEError;
    FCurrentEvent: TSSEEvent; // Moved from local to field
    AErrorMsg: string;

    FSocketFD: TSocket;
    procedure DoOpen;
    procedure DoClose;
    procedure DoEvent; // No parameters
    procedure DoError;
  protected
    procedure Execute; override;
  public
    constructor Create(const APreviousInteractionID: string; const APrompt: string);
    destructor Destroy; override;
    property OnEvent: TOnSSEEvent read FOnEvent write FOnEvent;
    property OnOpen: TOnSSEOpen read FOnOpen write FOnOpen;
    property OnClose: TOnSSEClose read FOnClose write FOnClose;
    property OnError: TOnSSEError read FOnError write FOnError;
  public
    property NewInteractionID: string read FNewInteractionID;
  end;

  TSSEClient = class
  private
    FThread: TSSEClientThread;
    FCurrentInteractionID: string; // Stores the latest interaction ID
    FOnEvent: TOnSSEEvent;
    FOnOpen: TOnSSEOpen;
    FOnClose: TOnSSEClose;
    FOnError: TOnSSEError;
    FChildProcess: TProcess; // Added FChildProcess to TSSEClient
    procedure OnThreadTerminated(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Connect(const APrompt: string);
    function IsActive: Boolean;
    property OnEvent: TOnSSEEvent read FOnEvent write FOnEvent;
    property OnOpen: TOnSSEOpen read FOnOpen write FOnOpen;
    property OnClose: TOnSSEClose read FOnClose write FOnClose;
    property OnError: TOnSSEError read FOnError write FOnError;
  end;

const UNIX_SOCKET_PATH = 'chat-router.sock';
implementation

{ TSSEClientThread }

constructor TSSEClientThread.Create(const APreviousInteractionID: string; const APrompt: string);
begin
  inherited Create(True);
  FPreviousInteractionID := APreviousInteractionID;
  FPrompt := APrompt;
  FreeOnTerminate := True;
  FillChar(FCurrentEvent, SizeOf(FCurrentEvent), 0);

  FSocketFD := TSocket(INVALID_SOCKET);
end;

destructor TSSEClientThread.Destroy;
begin

  if FSocketFD <> INVALID_SOCKET then
    CloseSocket(FSocketFD);
  inherited Destroy;
end;

procedure TSSEClientThread.DoOpen;
begin
  if Assigned(FOnOpen) then
    FOnOpen(Self);
end;

procedure TSSEClientThread.DoClose;
begin
  if Assigned(FOnClose) then
    FOnClose(Self);
end;

procedure TSSEClientThread.DoEvent;
begin
  if Assigned(FOnEvent) then
    FOnEvent(Self, FCurrentEvent);
end;

procedure TSSEClientThread.DoError;
begin
  if Assigned(FOnError) then
    FOnError(Self, AErrorMsg);
end;



procedure TSSEClientThread.Execute;
var
  SocketPath: string;
  Addr: sockaddr; // Keep generic sockaddr for now, cast inside IFDEF
  BytesSent: Integer;
  BytesReceived: Integer;
  Buffer: array[0..4095] of Byte;
  LineBuffer: string;
  Timeout: Integer;
  Retries: Integer;
  PrevInteractionID: string;
  MessageToSend: string;
  AppPath: string;
  NewLen: Integer;
  FirstLineEnd: Integer;
{$IFDEF USE_UNIX_SOCKETS}
  Addr_un: sockaddr_un;
{$ENDIF}
begin
  Synchronize(@DoOpen);
  AppPath := ExtractFilePath(Application.ExeName); // Get application directory

  try


    // 2. Setup Unix Domain Socket
    SocketPath := GetTempDir + PathDelim + UNIX_SOCKET_PATH;

    DebugLn('prepare connect socket');
    FSocketFD := fpsocket(AF_UNIX, SOCK_STREAM, 0);
    if FSocketFD = INVALID_SOCKET then
    begin
      AErrorMsg := 'Failed to create Unix domain socket.';
      DebugLn(AErrorMsg);
      Synchronize(@DoError);
      Exit;
    end;

    FillChar(Addr_un, SizeOf(Addr_un), 0);
    Addr_un.sun_family := AF_UNIX;
    StrPCopy(Addr_un.sun_path, SocketPath);

    // 3. Connect to the socket with retries
    Retries := 0;
    Timeout := 100; // milliseconds
    while (fpconnect(FSocketFD, @Addr_un, SizeOf(Addr_un)) <> 0) and (Retries < 50) and not Terminated do // Max 5 seconds retry
    begin
      if SocketError <> 0 then
      begin
        Inc(Retries);
        Sleep(Timeout);
      end
      else
      begin
        AErrorMsg := 'Failed to connect to Unix domain socket: ' + SysErrorMessage(SocketError);
      DebugLn(AErrorMsg);
        Synchronize(@DoError);
        CloseSocket(FSocketFD);
        FSocketFD := TSocket(INVALID_SOCKET);
        Exit; // Exit on connection error
    end; // This 'end' matches 'begin' on line 180
  end; // This 'end' matches 'begin' on line 173 (the while loop)

    if (Retries >= 50) or Terminated then
    begin
      AErrorMsg := 'Timed out or terminated while connecting to ChatRouter.exe socket.';
      Synchronize(@DoError);
      CloseSocket(FSocketFD);
      FSocketFD := TSocket(INVALID_SOCKET);
      Exit;
    end;

    PrevInteractionID := FPreviousInteractionID;
    MessageToSend := FPrompt;

    // 4. Send previous_interaction_id
    if PrevInteractionID = '' then
      BytesSent := fpsend(FSocketFD, PChar(#10 + #0), 1, 0) // Send newline for empty previous_interaction_id
    else
      BytesSent := fpsend(FSocketFD, PChar(PrevInteractionID + #10), Length(PrevInteractionID) + 1, 0);

    if BytesSent < 0 then
    begin
      AErrorMsg := 'Failed to send previous_interaction_id: ' + SysErrorMessage(SocketError);
      Synchronize(@DoError);
      CloseSocket(FSocketFD);
      FSocketFD := TSocket(INVALID_SOCKET);
      Exit;
    end;

    // 5. Send message
    BytesSent := fpsend(FSocketFD, PChar(MessageToSend + #10), Length(MessageToSend) + 1, 0);
    if BytesSent < 0 then
    begin
      AErrorMsg := 'Failed to send message: ' + SysErrorMessage(SocketError);
      Synchronize(@DoError);
      CloseSocket(FSocketFD);
      FSocketFD := TSocket(INVALID_SOCKET);
      Exit;
    end;

    // 6. Read response
    LineBuffer := '';
    while not Terminated do
    begin
      BytesReceived := fprecv(FSocketFD, @Buffer[0], SizeOf(Buffer), 0);
      if BytesReceived > 0 then
      begin
          NewLen := Length(LineBuffer) + BytesReceived;
          SetLength(LineBuffer, NewLen);
          Move(Buffer[0], LineBuffer[Length(LineBuffer) - BytesReceived + 1], BytesReceived);
      end
      else if BytesReceived = 0 then
      begin
        DebugLn('ChatRouter.exe closed connection. Full response received.');
        if LineBuffer <> '' then
        begin
          FirstLineEnd := Pos(#10, LineBuffer);
            if FirstLineEnd > 0 then
            begin
              FNewInteractionID := Trim(Copy(LineBuffer, 1, FirstLineEnd - 1));
              FCurrentEvent.Data := Copy(LineBuffer, FirstLineEnd + 1, Length(LineBuffer) - FirstLineEnd);
            end
            else // No newline, treat entire buffer as data (or error if ID is expected)
            begin
              FNewInteractionID := ''; // Or handle as an error if ID is mandatory
              FCurrentEvent.Data := LineBuffer;
            end;

          Synchronize(@DoEvent);
          FillChar(FCurrentEvent, SizeOf(FCurrentEvent), 0); // Clear FCurrentEvent
        end;
        Break;
      end
      else
      begin
        AErrorMsg := 'Error receiving data from socket: ' + SysErrorMessage(SocketError);
        Synchronize(@DoError);
        Break;
      end;
    end;

  finally
    if FSocketFD <> INVALID_SOCKET then
    begin
      CloseSocket(FSocketFD);
      FSocketFD := TSocket(INVALID_SOCKET);
    end; // Correctly close the 'if FSocketFD' block

    Synchronize(@DoClose);
  end;

end; // End of TSSEClientThread.Execute

{ TSSEClient }

constructor TSSEClient.Create;
begin
  inherited Create;
  FThread := nil;
  FChildProcess := nil; // Initialize FChildProcess
end;

destructor TSSEClient.Destroy;
begin
  if Assigned(FThread) then
  begin
    FThread.Terminate; // Request the thread to stop
    FThread.WaitFor;   // Wait for the thread to finish execution
    FThread.Free;      // Explicitly free the thread object
    FThread := nil;
  end;
  if Assigned(FChildProcess) then
  begin
    FChildProcess.Terminate(0);
    FChildProcess.Free;
    FChildProcess := nil;
  end;
  inherited Destroy;
end;

procedure TSSEClient.OnThreadTerminated(Sender: TObject);
begin
  if Assigned(FThread) then
  begin
    FCurrentInteractionID := FThread.NewInteractionID; // Update current interaction ID
    FThread := nil;
  end;
end;

procedure TSSEClient.Connect(const APrompt: string);
begin
  if IsActive then
    Exit;

  // Ensure ChatRouter.exe is running
  if not Assigned(FChildProcess) or not FChildProcess.Running then
  begin
    FChildProcess := TProcess.Create(nil);
    FChildProcess.Executable := ExtractFilePath(Application.ExeName) + 'ChatRouter.exe';
    DebugLn('Launching ChatRouter.exe from: ' + FChildProcess.Executable);
    FChildProcess.Options := [poUsePipes, poNoConsole];

    try
      FChildProcess.Execute;
      DebugLn('ChatRouter.exe launched successfully.');
      Sleep(500); // Give ChatRouter.exe some time to initialize
    except
      on E: EOSError do
      begin
        // Handle error: ChatRouter.exe failed to launch
        // This error should ideally be propagated or logged by TSSEClient
        DebugLn('Failed to launch ChatRouter.exe: ' + E.Message);
        FChildProcess.Free;
        FChildProcess := nil;
        Exit; // Exit Connect method if child process fails to launch
      end;
    end;
  end;

  if Assigned(FThread) then
  begin
      FThread.WaitFor;
  end;

  FThread := TSSEClientThread.Create(FCurrentInteractionID, APrompt);
  FThread.OnOpen := FOnOpen;
  FThread.OnClose := FOnClose;
  FThread.OnEvent := FOnEvent;
  FThread.OnError := FOnError;
  FThread.OnTerminate := @OnThreadTerminated;
  FThread.Start;
end;

function TSSEClient.IsActive: Boolean;
begin
  Result := Assigned(FThread) and not FThread.Terminated; // Fixed: Changed from FThread.Running
end;

end.
