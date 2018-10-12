unit uVNC;

{$mode objfpc}{$H+}
{hints off}

interface

uses
  Classes, SysUtils, FrameBuffer, WinSock2, uCanvas, SyncObjs, uAsync, uZLib;


const
  ft : array[boolean] of string = ('false', 'true');

  siOffline                        = 1;  // socket is offline
  siConnected                      = 2;  // socket has connected
  siProtocol                       = 3;  // socket deciding protocol
  siAuthenticate                   = 4;  // socket deciding authentication
  siSecurity                       = 8;  // socket deciding security
  siOnline                         = 5;  // socket communicating
  siClientInit                     = 6;
  siServerInit                     = 7;

  rfbConnFailed                    = 0;
  rfbNoAuth                        = 1;
  rfbVncAuth                       = 2;

  rfbVncAuthOK                     = 0;
  rfbVncAuthFailed                 = 1;
  rfbVncAuthTooMany                = 2;

  rfbFramebufferUpdate             = 0;
  rfbSetColourMapEntries           = 1;
  (* server -> client *)
  rfbBell                          = 2;
  rfbServerCutText                 = 3;
  (* client -> server *)
  rfbSetPixelFormat                = 0;
  rfbFixColourMapEntries           = 1; (* not currently supported *)
  rfbSetEncodings                  = 2;
  rfbFramebufferUpdateRequest      = 3;
  rfbKeyEvent                      = 4;
  rfbPointerEvent                  = 5;
  rfbClientCutText                 = 6;

  // encoding types   https://www.iana.org/assignments/rfb/rfb.xhtml
  rfbEncodingRaw                   = 0;
  rfbEncodingCopyRect              = 1;
  rfbEncodingRRE                   = 2;
  rfbEncodingCoRRE                 = 4;   // obsolete
  rfbEncodingHextile               = 5;
  rfbEncodingZLib                  = 6;
  rfbEncodingTight                 = 7;
  rfbEncodingZLibHex               = 8;
  rfbEncodingUltra                 = 9;
  rfbEncodingTRLE                  = 15;
  rfbEncodingZRLE                  = 16;
  rfbEncodingZYWRLE                = 17;
  rfbEncodingH264                  = 20;
  rfbEncodingJPEG                  = 21;
  rfbEncodingJRLE                  = 22;
  rfbEncodingVAH264                = 23;
  rfbEncodingZRLE2                 = 24;
  rfbEncodingCursor                = -239;   // pseudo
  rfbEncodingDesktopSize           = -223;  // pseudo

  rfbHextileRaw	                   = 1 shl 0;
  rfbHextileBackgroundSpecified	   = 1 shl 1;
  rfbHextileForegroundSpecified	   = 1 shl 2;
  rfbHextileAnySubrects	           = 1 shl 3;
  rfbHextileSubrectsColoured       = 1 shl 4;


type
  TVNCThread = class;

  TCard8 = byte;          // 8 bit cardinal
  PCard8 = ^TCard8;
  TCard16 = word;         // 16 bit cardinal
  PCard16 = ^TCard16;
  TCard32 = Cardinal;     // 32 bit cardinal
  PCard32 = ^TCard32;

  TTable8 = array [word] of TCard8;
  TTable16 = array [word] of TCard16;
  TTable32 = array [word] of TCard32;

  PTable8 = ^TTable8;
  PTable16 = ^TTable16;
  PTable32 = ^TTable32;

  TVNCPointerEvent = procedure (Sender : TObject; Thread : TVNCThread; x, y : TCard16; BtnMask : TCard8) of object;
  TVNCKeyEvent = procedure (Sender : TObject; Thread : TVNCThread; Key : TCard32; Down : boolean) of object;
  TVNCDrawEvent = procedure (Sender : TObject; Canvas : TCanvas; x, y, h, w : cardinal) of object;
  TVNCRectEvent = procedure (Sender : TObject; r : TRect) of object;

  TRectangle = record
    x, y : TCard16;
    w, h : TCard16;
  end;

  TFramebufferUpdateRectHeader = record
    r : TRectangle;
    encoding : TCard32;
  end;

  PFramebufferUpdateRectHeader = ^TFramebufferUpdateRectHeader;

  TPixelFormat = record
    BitsPerPixel : TCard8;
    Depth : TCard8;
    BigEndian : Boolean;
    TrueColour : Boolean;
    RedMax : TCard16;
    GreenMax : TCard16;
    BlueMax : TCard16;
    RedShift : TCard8;
    GreenShift : TCard8;
    BlueShift : TCard8;
  end;
  PPixelFormat = ^TPixelFormat;

  TTransFunc = procedure (Table : Pointer; InFormat, OutFormat : TPixelFormat;
                                iptr, optr : PByte;  BytesBetweenInputLines,  Width, Height : integer);


  TClientInitMsg = record
    shared : TCard8;
  end;

  TServerInitMsg = record
    FrameBufferWidth : TCard16;
    FrameBufferHeight : TCard16;
    PixFormat : TPixelFormat;
    NameLength : TCard32;
    (* followed by char name[nameLength] *)
  end;

  rfbCopyRect = record
    srcX,srcY : TCard16;
  end;

  rfbRREHeader = record
    nSubrects : TCard32;
  end;

  TFramebufferUpdateMsg = record
   msgType : TCard8; (* always rfbFramebufferUpdate *)
   pad : TCard8;
   nRects : TCard16;
  (* followed by nRects rectangles *)
  end;

  TSetPixelFormatMsg = record
    msgType : TCard8; (* always rfbSetPixelFormat *)
    pad1 : TCard8;
    pad2: TCard16;
    pixFormat : TPixelFormat;
    end;

  TFramebufferUpdateRequestMsg = record
    msgType : TCard8; (* always rfbFramebufferUpdateRequest *)
    incremental : TCard8;
    x : TCard16;
    y : TCard16;
    w : TCard16;
    h : TCard16;
  end;

  TPointerEventMsg = record
    msgType : TCard8; (* always rfbPointerEvent *)
    buttonMask: TCard8; (* bits 0-7 are buttons 1-8, 0=up, 1=down *)
    x : TCard16;
    y : TCard16;
  end;

  TKeyEventMsg = record
    msgType : TCard8; (* always rfbKeyEvent *)
    down : TCard8; (* true if down (press), false if up *)
    pad : TCard16;
    key : TCard32; (* key is specified as an X keysym *)
  end;

const
  SRectangle = SizeOf (TRectangle);
  SFramebufferUpdateRectHeader = SizeOf (TFrameBufferUpdateRectHeader);

  procedure test;

function Display (a: string): string;
function DisplayS (a: TStream): string;
function EncoderName (aType : integer) : string;

function Card8 (a: string; Index : integer) : TCard8;
function Card16 (a: string; Index : integer) : TCard16;
function Card32 (a: string; Index : integer) : TCard32;

function Str16 (Value: integer): string;
function Str32 (Value: cardinal): string;
function Str8 (Value: integer): string;

function Swap16IfLE (s: TCard16) : TCard16;
function Swap32IfLE (l: TCard32) : TCard32;

function Swap16 (Value : TCard16) : TCard16;
function Swap32 (Value: TCard32): TCard32;


type
  TVNCServer = class;
  TVNCResponse = class;

  { TVNCThread }
   TVNCThread = class (TWinsock2TCPServerThread)
    FOwner : TVNCServer;
    RxBuff : string;
    State : integer;
    RxID, RxLen : Word;
    RxUnitID : byte;
    FCanTRLE, FCanZRLE,
    FCanHextile, FCanResize : boolean;
    Prefered : integer;
  public
    Shared : boolean;
    VMajor, VMinor : integer;
    Response : TVNCResponse;
    PixelFormat : TPixelFormat;
    procedure ResponseReady;
    procedure Send (s : string);
  public
    constructor Create (aServer : TWinsock2TCPServer);
    destructor Destroy; override;
  end;

  { TVNCResponse }
  TVNCResponse = class (TThread)
    FOwner : TVNCThread;
    Stream : TMemoryStream;
    Rects : array of TRect;
    Back : TCard32;
    BackValid : boolean;
    Event : TEvent;
    zstream : TZStreamRec;
    zinit : boolean;
    count : integer;
    function TestColours (aRect : TRect; var bg : TCard32) : boolean;
    function EncodeRect (aRect : TRect) : boolean; // this maybe same as Rects size or a subrectangle if Rects is large
    procedure Execute; override;
    constructor Create (aThread : TVNCThread);
    destructor Destroy; override;
  end;

  { TVNCServer }
  TVNCServer = class (TWinsock2TCPListener)
  private
    FOnKey: TVNCKeyEvent;
    FOnPointer: TVNCPointerEvent;
    FOnGetRect : TVNCRectEvent;
    Height, Width : LongWord;
    VerMajor, VerMinor : integer;
    procedure DoCreateThread (aServer : TWinsock2TCPServer; var aThread : TWinsock2TCPServerThread);
  protected
    procedure DoConnect (aThread : TWinsock2TCPServerThread); override;
    procedure DoDisconnect (aThread : TWinsock2TCPServerThread); override;
    function DoExecute (aThread : TWinsock2TCPServerThread) : Boolean; override;
  public
    Title : string;
    Canvas : TCanvas;
    procedure InitCanvas (w, h : integer);
    constructor Create;
    destructor Destroy; override;
    property OnPointer : TVNCPointerEvent read FOnPointer write FOnPointer;
    property OnKey : TVNCKeyEvent read FOnKey write FOnKey;
    property OnGetRect : TVNCRectEvent read FOnGetRect write FOnGetRect;
  end;


  { TVNCClient }
  TVNCClient = class
    RxBuff : string;
    State : integer;
    FCanHextile, FCanResize : boolean;
    Thread : TThread;
  private
    FOnDraw: TVNCDrawEvent;
    Socket : TAsyncSocket;
    VerMajor, VerMinor : integer;
    procedure SocketConnected (Sender: TObject);
    procedure SocketClosed (Sender: TObject);
    procedure SocketRead (Sender: TObject; Buff: pointer; BuffSize: integer);
  public
    Height, Width : LongWord;
    Canvas : TCanvas;
    Addr : string;
    Port : Word;
    procedure Start;
    procedure Stop;
    constructor Create;
    procedure SendGetRect (x, y, h, w: Word); overload;
    procedure SendGetRect (r: TRect); overload;
    procedure SendKey (Key: Word; Down: boolean);
    procedure SendPointer (x, y: Word; BtnMask: byte);
    destructor Destroy; override;
    property OnDraw : TVNCDrawEvent read FOnDraw write FOnDraw;
  end;


implementation

uses uLog, GlobalConst;


const hello: PChar = 'hello, hello!';

const dictionary: PChar = 'hello';


procedure Add8 (aStream: TStream; aByte: TCard8);
begin
  aStream.Write (aByte, 1);
end;

procedure Add16 (aStream: TStream; aWord: TCard16);
var
  bWord : TCard16;
begin
  bWord := Swap16 (aWord);
  aStream.Write (bWord, 2);
end;

procedure Add32 (aStream: TStream; aDWord: TCard32);
var
  bDWord : TCard32;
begin
  bDWord := Swap32 (aDWord);
  aStream.Write (bDWord, 4);
end;

procedure AddPix (aStream: TStream; aPix: TCard32);  // translator added here
begin
  aStream.Write (aPix, 4);
end;

{ TVNCResponse }
function TVNCResponse.TestColours (aRect: TRect; var bg: TCard32): boolean;
var           // this checks if all poxels in rect are the same colour
  i, j : integer;
  first : boolean;
  aRow : PTable32;
begin
  first := true;
  Result := true;
  if FOwner = nil then exit;
  if FOwner.FOwner = nil then exit;
  if not Assigned (FOwner.FOwner.Canvas) then exit;
  for j := aRect.Top to aRect.Top + aRect.Bottom - 1 do
    begin
      aRow := FOwner.FOwner.Canvas.ScanLine (j);   // need to make this thread safe
      for i := aRect.Left to aRect.Left + aRect.Right - 1 do
        begin
          if first then bg := aRow^[i];
          first := false;
          if aRow^[i] = bg then continue;
          Result := false;
          exit;
        end;
    end;
end;

(*  No. of bytes Type [Value] Description
    1 U8 0 message-type
    1 padding
    2 U16 number-of-rectangles
        This is followed by number-of-rectangles rectangles of pixel data. Each rectangle
        consists of:
    No. of bytes Type [Value] Description
    2 U16 x-position
    2 U16 y-position
    2 U16 width
    2 U16 height
    4 S32 encoding-type     *)

function TVNCResponse.EncodeRect (aRect: TRect) : boolean;
var
  i, j : integer;
  w, h : TCard16;
  x, y : TCard16;
  xRect : TRect;
  bg : TCard32;
  aRow : PTable32;
  buff : pointer;
  bufflen : LongInt;
  err : integer;
  prev_out : integer;
begin
  Result := false;
  if FOwner = nil then exit;
  if FOwner.FOwner = nil then exit;
  if not Assigned (FOwner.FOwner.Canvas) then exit;
//  Log ('Encoding Rect ' + aRect.Width.tostring + ' by ' + aRect.Height.ToString + ' @ ' + aRect.Left.ToString + ',' + aRect.Top.ToString);
  Add16 (Stream, aRect.Left);         //  X - Position
  Add16 (Stream, aRect.Top);          //  Y - Position
  Add16 (Stream, aRect.Right);        //  Width
  Add16 (Stream, aRect.Bottom);       //  Height

  case FOwner.Prefered of
    rfbEncodingRaw :
      begin
        Add32 (Stream, rfbEncodingRaw); // raw encoding
        for j := aRect.Top to  aRect.Top + aRect.Bottom - 1 do
           begin
            aRow := FOwner.FOwner.Canvas.ScanLine(j);  // need to make this thread safe
            for i := aRect.Left to aRect.Left + aRect.Right - 1 do
              AddPix (Stream, aRow^[i]);    // needs translation
           end;
      end;
    rfbEncodingHextile :
      begin
        Add32 (Stream, rfbEncodingHextile); // hextile encoding
        y := aRect.Top;
        while y < aRect.Top + aRect.Bottom do
          begin
            if y + 16 < aRect.Top + aRect.Bottom then
              h := 16
            else
              h := aRect.Top + aRect.Bottom - y;
            x := aRect.Left;
            while x < aRect.Left + aRect.Right do
              begin
                if x + 16 < aRect.Left + aRect.Right then
                  w := 16
                else
                  w := aRect.Left + aRect.Right - x;
                xRect := Rect (x, y, w, h);
                if TestColours (xRect, bg) then
                  begin
                    if (bg <> back) or (not BackValid) then
                      begin
                        back := bg;
                        BackValid := true;
                    //    Log ('Back Colour  ' + back.ToHexString (8));
                        // this is encoded with new back colour
                        Add8 (Stream, rfbHextileBackgroundSpecified);  // background
                        AddPix (Stream, back);  // background colour
                      end
                    else
                      begin
                        // this is encoded using existing back colour
                        Add8 (Stream, 0);   // no background specified
                      end;
                  end
                else
                  begin
                    // this is encoded as raw
                    BackValid := false;
                    Add8 (Stream, rfbHextileRaw);                 // raw encoded
                    for j := y to y + h - 1 do
                      begin
                        aRow := FOwner.FOwner.Canvas.ScanLine(j);  // need to make this thread safe
                        for i := x to x + w - 1 do
                          AddPix (Stream, aRow^[i]);    // needs translation
                      end;
                  end;
                x := x + 16;
              end;  // while x
            y := y + 16;
          end;    // while y

      end; // hextile
    rfbEncodingZLib :
      begin


        Add32 (Stream, rfbEncodingZLib); // ZLib encoding
        if not zinit then
          begin
            zstream.zalloc := nil;
	          zstream.zfree := nil;
	          zstream.opaque := nil;
	          zinit := deflateInit (zstream, Z_DEFAULT_COMPRESSION) = Z_OK;
            if not zinit then Log ('ZLIB Init Failure.') else Log ('Zlib Init Success.');
            zstream.total_out := 0;
          end;
        i := aRect.Left;
        y := aRect.Top;
        if aRect.Left + aRect.Right <= FOwner.FOwner.Width then
          w := aRect.Right
        else
          w := FOwner.FOwner.Width - aRect.Left;
        if aRect.Top + aRect.Bottom <= FOwner.FOwner.Height then
          h := aRect.Bottom
        else
          h := FOwner.FOwner.Height - aRect.Top;
        bufflen := (w * h * 4) * 40;
        buff := AllocMem (bufflen);
        zstream.next_out := buff;
        zstream.avail_out := bufflen;
        prev_out := zstream.total_out;
        Log ('Width ' + w.ToString + ' Height ' + h.ToString);

        zstream.next_in := PChar (FOwner.FOwner.Canvas.Buffer);
        zstream.avail_in := w * h * 4;

        Log ('About to deflate');
        err := deflate (zstream, Z_FULL_FLUSH);
        Log ('Deflate result ' + err.ToString);
     (*   for j := y to y + h - 1 do
          begin
            aRow := FOwner.FOwner.Canvas.ScanLine(j);  // need to make this thread safe
            zstream.next_in := @aRow^[i];
            zstream.avail_in := w * 4;   // w pixels

            err := deflate (zstream, Z_NO_FLUSH);
       //     Log ('Row ' + j.ToString + ' deflate ' + err.ToString + ' total out ' + zstream.total_out.ToString);


          end;     *)

          Log ('Total Out ' + zstream.total_out.ToString);
        Add32 (Stream, zstream.total_out);
        Stream.Write (buff^, zstream.total_out);
        deflateReset (zstream);
       // zinit := false;
        FreeMem (buff);
      end;
    rfbEncodingZRLE :
      begin
        Add32 (Stream, rfbEncodingZRLE); // ZRLE encoding

	      zstream.zalloc := nil;
	      zstream.zfree := nil;
	      zstream.opaque := nil;

	      if deflateInit (zstream, Z_DEFAULT_COMPRESSION) = Z_OK then
          begin
          end;

        (*
//reduce the BMP header size from total length
uLongf sourceLen = DATA_SIZE-0x436;
//add sufficient length for encoding algorithm
uLongf destLen = (sourceLen*1.001)+12;
unsigned char* compressedBuffer = (unsigned char* )malloc(destLen);
         zlibstream.next_in = (Bytef* )pixelDataBuffer;
zlibstream.avail_in = (uInt)sourceLen;
zlibstream.next_out = compressedBuffer;
zlibstream.avail_out = (uInt)destLen;
previous_out = zlibstream.total_out;

printf("before deflate \r\n");
//Apply ZLIB encoding to the pixel buffer
zliberr = deflate(&zlibstream, Z_SYNC_FLUSH);

destLen = zlibstream.total_out - previous_out;

printf("zlib data length = %d \r\n", destLen);
unsigned char zlibHeader[4];
UINT32 zlibLength = destLen;
zlibHeader[0] = zlibLength>>24; zlibHeader[1] = zlibLength>>16; zlibHeader[2] = zlibLength>>8; zlibHeader[3] = zlibLength;

//Send length of the zlib buffer
iSendResult = send( ClientSocket, (const char* )zlibHeader, 4, 0 );
if(iSendResult==SOCKET_ERROR){return 1;}

//send zlib encoded pixel data
iSendResult = send( ClientSocket, (const char* )compressedBuffer, destLen, 0 );

//Free the buffer
free(compressedBuffer);        *)

        y := aRect.Top;
        while y < aRect.Top + aRect.Bottom do

          begin
            if y + 64 < aRect.Top + aRect.Bottom then
              h := 64
            else
              h := aRect.Top + aRect.Bottom - y;
            x := aRect.Left;
            while x < aRect.Left + aRect.Right do
              begin
                if x + 64 < aRect.Left + aRect.Right then
                  w := 64
                else
                  w := aRect.Left + aRect.Right - x;
                xRect := Rect (x, y, w, h);



                x := x + 64;
              end;  // while x
            y := y + 64;
          end;    // while y

      end;
      end;   // case
  Result := true;
end;

procedure TVNCResponse.Execute;
var
  k : integer;
begin
  if FOwner = nil then exit;
  while not Terminated do
    begin
      Event.WaitFor (INFINITE);       // park thread
      Event.ResetEvent;
      count := count + 1;
      if count < 3 then
        begin
      Add8 (Stream, 0);                 // Msg Type
      Add8 (Stream, 0);                 // padding
      Add16 (Stream, length (Rects));   // nos rect
      for k := 0 to length (Rects) - 1 do EncodeRect (Rects[k]);
      FOwner.ResponseReady;
      Back := 0;
      BackValid := false;
      Stream.Clear;

        end;
    end;
end;

constructor TVNCResponse.Create (aThread: TVNCThread);
begin
  inherited Create (true);
  FOwner := aThread;
  Back := 0;
  BackValid := false;
  SetLength (Rects, 1);  // currently only have a single rect
  zinit := false;
  count := 0;
  Stream := TMemoryStream.Create;
  Event := TEvent.Create (nil, true, false, '');
  Start;
end;

destructor TVNCResponse.Destroy;
begin
  Stream.Free;
  Event.Free;
  inherited Destroy;
end;

{ TVNCClient }
procedure TVNCClient.SocketConnected (Sender: TObject);
begin
  Log ('Socket Connected');
  State := siProtocol;
end;

procedure TVNCClient.SocketClosed (Sender: TObject);
begin
  Log ('Socket Closed');
end;

procedure TVNCClient.SocketRead (Sender: TObject; Buff: pointer;
  BuffSize: integer);
var
  s : string;
  i : Cardinal;
  loop : boolean;

begin
  i := length (RxBuff);
  Setlength (RxBuff, i + BuffSize);
  Move (Buff^, RxBuff[i + 1], Buffsize);
 // Log ('Socket Read "' + display (s) + '"  ' + IntToStr (BuffSize) + ' bytes.');
  Log ('Socket Read ' + IntToStr (BuffSize) + ' bytes.');
  loop := true;
  while loop do
    case State of
      siProtocol :
        begin
          if (Length (RxBuff) >= 12) then
            begin
              if (Copy (RxBuff, 1, 3) = 'RFB') then
                begin
                  State := siAuthenticate;
                  VerMajor := StrToIntDef (Copy (RxBuff, 5, 3), 0);
                  VerMinor := StrToIntDef (Copy (RxBuff, 9, 3), 0);
                  Log (Format ('Version %d.%d.', [VerMajor, VerMinor]));
                  RxBuff := Copy (RxBuff, 13);
                  Socket.Send (Format ('RFB %.3d.%.3d'#10, [VerMajor, VerMinor]));
                end
              else
                begin
                  Log ('Protocol failed.');
                  RxBuff := '';
                  loop := false;
                  Socket.Disconnect;
                end
            end
          else
            loop := false;
        end; // protocol
      siAuthenticate :
        begin
        Log ('Authentication ' + length (RxBuff).ToString);
        if (length (RxBuff) >= 4) then
          begin
            i := Card32 (rxBuff, 1);
            Log ('Authentication ' + i.ToHexstring (8));
            RxBuff := Copy (RxBuff, 5);
            State := siConnected;
          end
        else
          loop := false;
        end;
      else
        begin
          RxBuff := '';
          loop := false;
        end;
    end; // case  / loop
end;

procedure TVNCClient.Start;
begin
  if not (Socket.State in [stInit, stClosed]) then exit;
  Socket.Addr := Addr;
  Socket.Port := Port;
  Socket.Connect;
end;

procedure TVNCClient.Stop;
begin
  Socket.Disconnect;
end;

constructor TVNCClient.Create;
begin
  Addr := '127.0.0.1';
  Port := 5900;
  VerMajor := 3;
  VerMinor := 3;
//  TxBuff := TMemoryStream.Create;
  RxBuff := '';
  // create async socket
  Socket := TAsyncSocket.Create;
  // socket events
  Socket.OnConnect := @SocketConnected;
  Socket.OnClose := @SocketClosed;
  Socket.OnRead := @SocketRead;
end;

procedure TVNCClient.SendGetRect (r: TRect);
begin
  // todo
end;

procedure TVNCClient.SendGetRect (x, y, h, w: Word);
begin
  // todo
end;

procedure TVNCClient.SendKey (Key: Word; Down: boolean);
begin
  // todo
end;

procedure TVNCClient.SendPointer (x, y: Word; BtnMask: byte);
begin
  // todo
end;

destructor TVNCClient.Destroy;
begin
  Stop;
  Socket.Free;
  inherited Destroy;
end;

{ TVNCThread }
procedure TVNCThread.Send (s: string);
begin
  try
    Server.WriteData (@s[1], length (s));
  except
    end;
end;

constructor TVNCThread.Create (aServer: TWinsock2TCPServer);
begin
  inherited Create (aServer);
  RxBuff := '';
  Prefered := -1;
  Response := TVNCResponse.Create (Self);
end;

destructor TVNCThread.Destroy;
begin
  Response.Free;
  inherited Destroy;
end;

procedure TVNCThread.ResponseReady;
begin
  if (Response <> nil) and (FOwner <> nil) then
    begin
      if Response.Stream.Size > 0 then
        try
          Server.WriteData (Response.Stream.Memory, Response.Stream.Size);
        except
          end;
      Response.Stream.Clear;
    end;
end;

{ TVNCServer }
procedure TVNCServer.DoCreateThread (aServer: TWinsock2TCPServer;
  var aThread: TWinsock2TCPServerThread);
begin
  aThread := TVNCThread.Create (aServer);
  with TVNCThread (aThread) do
    begin
      FOwner := Self;
      State := siOffline;
    end;
end;

procedure TVNCServer.DoConnect (aThread: TWinsock2TCPServerThread);
var
  aVNCThread : TVNCThread;
  tmp : string;
begin
  inherited DoConnect (aThread);
  aVNCThread := TVNCThread (aThread);
  Log ('Client Connected.');
  with aVNCThread do
    begin
      State := siProtocol;
      tmp := format ('RFB %.3d.%.3d'#10, [VerMajor, VerMinor]);
      try
        Server.WriteData (@tmp[1], length (tmp));
      except
        end;
    end;
end;

procedure TVNCServer.DoDisconnect (aThread: TWinsock2TCPServerThread);
begin
  inherited DoDisconnect (aThread);
  Log ('Client Disconnected.');
end;

function TVNCServer.DoExecute (aThread: TWinsock2TCPServerThread): Boolean;
var
  Pixs, tmp : string;
  i : integer;
  a, b : TCard16;
  x, y, w, h : TCard16;
  BtnMask : TCard8;
  aVNCThread : TVNCThread;
  KeyDown : boolean;
  Key : TCard32;
  closed, d, loop : boolean;
  c : integer;
  buff : array [0..255] of byte;
begin
  Result := inherited DoExecute (aThread);
  if not Result then exit;
  aVNCThread := TVNCThread (aThread);
  c := 256;
  closed := false;
  d := aThread.Server.ReadAvailable (@buff[0], 255, c, closed);
  if closed or not d then Result := false;
  if (c = 0) or closed then exit;
//  Log ('Read ' + inttostr (c) + ' bytes.');
  with aVNCThread do
    begin
      i := Length (RxBuff);
      Setlength (RxBuff, i + c);
      Move (buff[0], RxBuff[i + 1], c);
      loop := true;
      while loop do
        case State of
          siProtocol :
            begin
              if (Length (RxBuff) >= 12) then
                begin
                  if Copy (RxBuff, 1, 3) = 'RFB' then
                    begin
                      VMajor := StrToIntDef (Copy (RxBuff, 5, 3), 0);
                      VMinor := StrToIntDef (Copy (RxBuff, 9, 3), 0);
                      Log (format ('Using Version %d.%d.', [VMajor, VMinor]));
                      if VMajor = 3 then
                        begin
                          if VMinor = 8 then // 3.8
                            begin
                              State := siSecurity;
                              Send (#1#1); // 1 security - none
                            end
                          else if VMinor = 3 then // 3.3
                            begin
                              State := siAuthenticate;
                              Send (#0#0#0#1);
                            end
                          else
                            begin // bad version
                              Result := false;
                              exit;
                            end;
                        end
                      else
                        begin  // bad version
                          Result := false;
                          exit;
                        end;
                      RxBuff := Copy (RxBuff, 13);
                    end
                  else
                    begin
                      Log ('Protocol failed.');
                      Result := false;
                      exit;
                    end;
                end
              else
                Loop := false; // need more bytes
            end;
          siSecurity :
            begin
              if Length (RxBuff) >= 1 then
                begin
                  Log ('Security ' + IntToStr (ord (RxBuff[1])));
                  if RxBuff[1] = #1 then
                    begin
                      State := siAuthenticate;
                      Send (#0#0#0#0);  // SecurityResult Handshake 0 = OK
                    end
                  else
                    begin
                      Result := false;
                      exit;
                    end;
                  RxBuff := Copy (RxBuff, 2);
                end
              else
                Loop := false;
            end;
          siAuthenticate :
            begin
              if Length (RxBuff) >= 1 then
                begin
                  Shared := Copy (RxBuff, 1, 1) <> #0;
                  RxBuff := Copy (RxBuff, 2);
                  State := siConnected;
              (*  1 U8 bits-per-pixel
                  1 U8 depth
                  1 U8 big-endian-flag
                  1 U8 true-colour-flag
                  2 U16 red-max
                  2 U16 green-max
                  2 U16 blue-max
                  1 U8 red-shift
                  1 U8 green-shift
                  1 U8 blue-shift
                  3 padding   *)
                  Pixs := #32#24#0#1#0#255#0#255#0#255#16#8#0#0#0#0;
              (*  No. of bytes Type [Value] Description
                  2 U16 framebuffer-width
                  2 U16 framebuffer-height
                  16 PIXEL_FORMAT server-pixel-format
                  4 U32 name-length
                  name-length U8 array name-string  *)
                  tmp := Str16 (Width) +
                         Str16 (Height) +
                         Pixs +
                         Str32 (length (Title)) +
                         Title;
      //          Log (display (tmp));
                  Send (tmp);
                  RxBuff := Copy (RxBuff, 2);
                end
              else
                Loop := false;
            end;
          siConnected :
            begin
         //     Log ('Connected .......');
              if Length (RxBuff) >= 1 then
                case Card8 (RxBuff, 1) of
                   0 :
                      begin
                        Log ('Set Pixel Format');
                        if Length (RxBuff) >= 20 then
                          with PixelFormat do
                            begin
                              BitsPerPixel := Card8 (RxBuff, 5);
                              Depth := Card8 (RxBuff, 6);
                              BigEndian := Card8 (RxBuff, 7) <> 0;
                              TrueColour := Card8 (RxBuff, 8) <> 0;
                              RedMax := Card16 (RxBuff, 9);
                              GreenMax := Card16 (RxBuff, 11);
                              BlueMax := Card16 (RxBuff, 13);
                              RedShift := Card8 (RxBuff, 15);
                              GreenShift := Card8 (RxBuff, 16);
                              BlueShift := Card8 (RxBuff, 17);
                              Log ('  BitsPerPixel'#9': ' + IntToStr (BitsPerPixel));
                              Log ('  Depth       '#9': ' + IntToStr (Depth));
                              Log ('  Big Endian  '#9': ' + ft[BigEndian]);
                              Log ('  True Colour '#9': ' + ft[TrueColour]);
                              Log ('  Red Max     '#9': ' + IntToStr (RedMax));
                              Log ('  Green Max   '#9': ' + IntToStr (GreenMax));
                              Log ('  Blue Max    '#9': ' + IntToStr (BlueMax));
                              Log ('  Red Shift   '#9': ' + IntToStr (RedShift));
                              Log ('  Green Shift '#9': ' + IntToStr (GreenShift));
                              Log ('  Blue Shift  '#9': ' + IntToStr (BlueShift));
                              RxBuff := Copy (RxBuff, 21);
                            end   // with
                          else Loop := false;
                      end;
                    1 :
                      begin
                        Log ('Fix Color Map Entries.');
                        RxBuff := '';
                        Loop := false;
                      end;
                    2 :
                      begin
                        Log ('Set Encodings.');
                        if Length (RxBuff) >= 4 then
                          begin
                            a := card16 (RxBuff, 3);
                            Log ('  Nos encodings : ' + IntToStr (a));
                            if Length (RxBuff) >= 5 * a then
                              begin
                                for b := 1 to a do
                                  begin
                                    i := integer (card32 (RxBuff, 5 + ((b - 1) * 4)));
                                    Log ('  Encoding ' + IntToStr (b) + #9': ' + EncoderName (i));
                                    if i = rfbEncodingHextile then FCanHextile := true;
                                    if i = rfbEncodingDesktopSize then FCanResize := true;
                                    if (Prefered < 0) and (i in [rfbEncodingRaw, rfbEncodingHextile {,rfbEncodingTRLE,} {rfbEncodingZRLE}]) then
                                       Prefered := i;
                                  end;
                                if Prefered < 0 then Prefered := rfbEncodingRaw;
                            //    Log ('  Can Hextile '#9': ' + ft[FCanHextile]);
                            Prefered := rfbEncodingZlib;
                                Log ('Prefered Encoding ' + EncoderName (Prefered));
                                Log ('  Can Resize  '#9': ' + ft[FCanResize]);
                                RxBuff := Copy (RxBuff, 5 + (4 * a));
                              end
                            else
                              Loop := false;
                          end
                        else
                          Loop := false;
                      end;
                    3 :
                      begin
               //       incremental := Card8 (RxBuff, 2);
                        x := Card16 (RxBuff, 3);
                        y := Card16 (RxBuff, 5);
                        w := Card16 (RxBuff, 7);
                        h := Card16 (RxBuff, 9);
                        if (w = Width) and (h = Height) then
                          begin
                            with Response.Rects[0] do
                              begin
                                Left := x;
                                Top := y;
                                Right := w;
                                Bottom := h;
                              end;
                            RxBuff := Copy (RxBuff, 11);
                            if Assigned (FOnGetRect) then FonGetRect (aVNCThread, Response.Rects[0]);
                            Response.Event.SetEvent;
                          end;

                    (*    if (w = Width) and (h = Height) then
                          a := 1
                        else
                          a := Length (Response.Rects) + 1;
                        SetLength (Response.Rects, a);
                        with Response.Rects[a - 1] do
                          begin
                            Left := x;
                            Top := y;
                            Right := w;
                            Bottom := h;
                          end;
   //                     Log ('Rects Pending'#9': ' + IntToStr (a));      *)
                    (*    RxBuff := Copy (RxBuff, 11);
                        if Assigned (FOnGetRect) then FonGetRect (aVNCThread, Response.Rects[0]);

                        Response.Event.SetEvent;          *)
                      end;
                    4 :   // key event
                      begin           // 8 bytes
                        if Length (RxBuff) >= 8 then
                          begin
                            KeyDown := Card8 (RxBuff, 2) = 1;
                            Key := Card32 (RxBuff, 5);
                            if Assigned (FOnKey) then FOnKey (Self, aVNCThread, Key, KeyDown);
                            RxBuff := Copy (RxBuff, 9);
                          end
                        else
                          Loop := false;
                      end;
                    5 :  // pointer event
                      begin          //  6 bytes long
                        if Length (RxBuff) >= 6 then
                          begin
                            BtnMask := Card8 (RxBuff, 2);
                            a := Card16 (RxBuff, 3);
                            b := Card16 (RxBuff, 5);
                            if Assigned (FOnPointer) then FOnPointer (Self, aVNCThread, a, b, BtnMask);
                            RxBuff := Copy (RxBuff, 7);
                          end
                        else
                          Loop := false;
                      end;
                  6 :  // client cut text
                      begin   //  6 bytes long
                        if Length (RxBuff) >= 6 then
                          begin
                            Log ('Client Cut Text.');
                            a := Card32 (RxBuff, 3);
                            RxBuff := Copy (RxBuff, 9 + a);
                          end
                        else
                          Loop := false;
                      end;
                    else
                      begin
                        Log ('Garbage.');
                        RxBuff := '';
                        Loop := false;
                      end;
                  end      // case
               else
                 Loop := false;
            end;  // connected
        end;  // case / while
    end;
end;

procedure TVNCServer.InitCanvas (w, h: integer);
begin
  Width := w;
  Height := h;
  if Assigned (Canvas) then Canvas.Free;
  Canvas := TCanvas.Create;
  Canvas.SetSize (w, h, COLOR_FORMAT_ARGB32);
end;

constructor TVNCServer.Create;
begin
  inherited Create;
  BoundPort := 5900;
  OnCreateThread := @DoCreateThread;
  Width := 0;
  Height := 0;
  Canvas := nil;
  VerMajor := 3;
  VerMinor := 8;
end;

destructor TVNCServer.Destroy;
begin
  if Assigned (Canvas) then Canvas.Free;
  inherited Destroy;
end;

function Display (a: string): string;
var
  i : integer;
begin
  Result := '';
  for i := 1 to length(a) do
    begin
      if CharInSet (a[i], [' '..'z']) then
        Result := Result + a[i]
      else
        Result := Result + '<' + IntToStr (ord (a[i])) + '>';
   end;
end;

function DisplayS (a: TStream): string;
var
//  i : integer;
  b : Char;
  x : int64;
begin
  Result := '';
  b := #0;
  x := a.Position;
  a.Seek (0, soFromBeginning);
  while a.Position <> a.Size do
    begin
      a.read (b, 1);
//      if CharInSet (b, [' '..'z']) then
  //      Result := Result + b
    //  else
        Result := Result + '<' + IntToStr (ord (b)) + '>';
    end;
  a.Seek (x, soFromBeginning);
end;

function EncoderName (aType: integer) : string;
begin
  case aType of
    rfbEncodingRaw         : Result := 'Raw';
    rfbEncodingCopyRect    : Result := 'Copy Rect';
    rfbEncodingRRE         : Result := 'RRE';
    rfbEncodingCoRRE       : Result := 'CoRRE';
    rfbEncodingHextile     : Result := 'Hextile';
    rfbEncodingZLib        : Result := 'ZLib';
    rfbEncodingTight       : Result := 'Tight';
    rfbEncodingZLibHex     : Result := 'ZLib Hex';
    rfbEncodingUltra       : Result := 'Ultra';
    rfbEncodingTRLE        : Result := 'TRLE';
    rfbEncodingZRLE        : Result := 'ZRLE';
    rfbEncodingZYWRLE      : Result := 'ZYWRLE';
    rfbEncodingH264        : Result := 'H.264';
    rfbEncodingJPEG        : Result := 'JPEG';
    rfbEncodingJRLE        : Result := 'JRLE';
    rfbEncodingVAH264      : Result := 'VA H.264';
    rfbEncodingZRLE2       : Result := 'ZRLE2';
    rfbEncodingCursor      : Result := 'Cursor (pseudo)';
    rfbEncodingDeskTopSize : Result := 'DeskTopSize (pseudo)';
    else                     Result := 'Unknown (' + IntToStr (aType) + ')';
    end;
end;

function Card16 (a: string; Index: integer) : TCard16;
begin
  if Index + 1 > Length (a) then
    Result := 0
  else
   Result := (ord (a[index]) * $100) + ord (a[index + 1]);
end;

function Card32 (a: string; Index: integer) : TCard32;
begin
  if Index + 3 > Length (a) then
    Result := 0
  else
    Result := (ord (a[index]) * $1000000) + (ord (a[index + 1]) * $10000) +
              (ord (a[index + 2]) * $100) + ord (a[index + 3]);
end;

function Card8 (a: string; Index: integer) : TCard8;
begin
 if Index > Length (a) then
    Result := 0
 else
  Result := ord (a[index]);
end;

function Str16 (Value: integer) : string;
begin
  Result := Char (Value div $100) + Char (Value mod $100);
end;

function Str32 (Value: cardinal) : string;
var
  i : integer;
  Reduce : cardinal;
begin
  Result := '';
  Reduce := Value;
  for i := 1 to 4 do
    begin
      Result := Char (Reduce mod $100) + Result;
      Reduce := Reduce div $100;
    end;
end;

function Str8 (Value: integer): string;
begin
  Result := AnsiChar (Value);
end;

function Swap16IfLE (s : TCard16) : TCard16;
begin
  Result := ((s and $ff) shl 8) or ((s shl 8) and $ff);
end;

function  Swap32IfLE (l : TCard32) : TCard32;
begin
  Result := ((l and $ff000000) shl 24) or
            ((l and $00ff0000) shl 8) or
            ((l and $0000ff00) shr 8) or
            ((l and $000000ff) shr 24);
end;

function Swap16 (Value : TCard16) : TCard16;
begin
  Result := (lo (Value) << 8) + hi (Value);
end;

function Swap32 (Value: TCard32): TCard32;
var
  l, h : word;
begin
  l := lo (Value);
  h := hi (Value);
  Result := ((lo (l) shl 8) + hi (l)) shl 16;
  Result := Result + (lo (h) shl 8) + hi (h);
end;

procedure CHECK_ERR (err: Integer; msg: String);
begin
  if err <> Z_OK then
  begin
    Log (msg + ' error: ' + err.ToString);
  //  Halt(1);
  end
  else
    Log (msg + ' success');
end;

procedure test;
var
 zlibstream : TZStreamRec;
 zliberr : integer;
 compr : pointer;
 comprlen : LongInt;
 len : integer;
begin
  ComprLen := 10000 * SizeOf (integer);

  GetMem (compr, comprLen);
  FillChar (compr^, comprLen, 0);
  len := StrLen (hello);

  zlibstream.zalloc := nil;
  zlibstream.zfree := nil;
  zlibstream.opaque := nil;

 	zliberr := deflateInit (zlibstream, Z_DEFAULT_COMPRESSION);
	if zliberr <> Z_OK then
	  log ('deflate init failed.')
  else
    log ('deflate init OK');
  zlibstream.next_in := hello;
  zlibstream.next_out := compr;

  while (zlibstream.total_in <> len) and
        (zlibstream.total_out < comprLen) do
  begin
    zlibstream.avail_out := 1; { force small buffers }
    zlibstream.avail_in := 1;
    zliberr := deflate (zlibstream, Z_NO_FLUSH);
    CHECK_ERR(zliberr, 'deflate');
  end;

  (* Finish the stream, still forcing small buffers: *)
  while TRUE do
  begin
    zlibstream.avail_out := 1;
    zliberr := deflate(zlibstream, Z_FINISH);
    if zliberr = Z_STREAM_END then break;
    CHECK_ERR(zliberr, 'deflate');
  end;

  zliberr := deflateEnd(zlibstream);
  CHECK_ERR(zliberr, 'deflateEnd');


           (*

  var err: Integer;
    d_stream: z_stream; ( * decompression stream * )
begin
  StrCopy(PChar(uncompr), 'garbage');

  d_stream.zalloc := NIL;
  d_stream.zfree := NIL;
  d_stream.opaque := NIL;

  d_stream.next_in := compr;
  d_stream.avail_in := 0;
  d_stream.next_out := uncompr;

  err := inflateInit(d_stream);
  CHECK_ERR(err, 'inflateInit');

  while (d_stream.total_out < uncomprLen) and
        (d_stream.total_in < comprLen) do
  begin
    d_stream.avail_out := 1; (* force small buffers *)
    d_stream.avail_in := 1;
    err := inflate(d_stream, Z_NO_FLUSH);
    if err = Z_STREAM_END then
      break;
    CHECK_ERR(err, 'inflate');
  end;

  err := inflateEnd(d_stream);
  CHECK_ERR(err, 'inflateEnd');

  if StrComp(PChar(uncompr), hello) <> 0 then
    EXIT_ERR('bad inflate')
  else
    WriteLn('inflate(): ', PChar(uncompr));

             *)
 end;

(*
//==============================================================================
if(!bFirstUpdateSent)
{
	zlibstream.zalloc = (alloc_func)0;
	zlibstream.zfree = (free_func)0;
	zlibstream.opaque = (voidpf)0;

	//Initialize the ZLIB for the first time
	printf("before deflateInit \r\n");
	zliberr = deflateInit(&zlibstream, Z_DEFAULT_COMPRESSION);
	if (zliberr != Z_OK)
	{
		printf("deflateInit failed \r\n");
	}
}
bFirstUpdateSent = TRUE;

//reduce the BMP header size from total length
uLongf sourceLen = DATA_SIZE-0x436;
//add sufficient length for encoding algorithm
uLongf destLen = (sourceLen*1.001)+12;
unsigned char* compressedBuffer = (unsigned char* )malloc(destLen);
zlibstream.next_in = (Bytef* )pixelDataBuffer;
zlibstream.avail_in = (uInt)sourceLen;
zlibstream.next_out = compressedBuffer;
zlibstream.avail_out = (uInt)destLen;
previous_out = zlibstream.total_out;

printf("before deflate \r\n");
//Apply ZLIB encoding to the pixel buffer
zliberr = deflate(&zlibstream, Z_SYNC_FLUSH);

destLen = zlibstream.total_out - previous_out;

printf("zlib data length = %d \r\n", destLen);
unsigned char zlibHeader[4];
UINT32 zlibLength = destLen;
zlibHeader[0] = zlibLength>>24; zlibHeader[1] = zlibLength>>16; zlibHeader[2] = zlibLength>>8; zlibHeader[3] = zlibLength;

//Send length of the zlib buffer
iSendResult = send( ClientSocket, (const char* )zlibHeader, 4, 0 );
if(iSendResult==SOCKET_ERROR){return 1;}

//send zlib encoded pixel data
iSendResult = send( ClientSocket, (const char* )compressedBuffer, destLen, 0 );

//Free the buffer
free(compressedBuffer);
//==============================================================================
*)

end.

