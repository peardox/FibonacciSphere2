{ Main state, where most of the application logic takes place.

  Feel free to use this code as a starting point for your own projects.
  (This code is in public domain, unlike most other CGE code which
  is covered by the LGPL license variant, see the COPYING.txt file.) }
unit GameStateMain;

interface

uses Classes, Math,
  CastleVectors, CastleUIState, CastleComponentSerialize,
  CastleUIControls, CastleControls, CastleKeysMouse, CastleViewport,
  CastleCameras, CastleApplicationProperties, CastleSceneCore,
  CastleWindow, CastleScene, X3DNodes, X3DFields, X3DLoad, CastleTimeUtils;

type
  TStringArray = Array of String;
  TModelArray = Array of TX3DRootNode;

  { TCastleSceneHelper }
  TCastleSceneHelper = class helper for TCastleScene
  public
    function Normalize: TVector3;
    function IsVisible: Boolean;
  end;

  { TCastleViewportHelper }
  TCastleViewportHelper = class helper for TCastleViewport
  public
    procedure ViewFromRadius(const ARadius: Single; const ADirection: TVector3);
    procedure ViewFromRadius(const ARadius: Single; const AElevation: Single; const ATheta: Single);
  end;

  { Main state, where most of the application logic takes place. }
  TStateMain = class(TUIState)
  private
    { Components designed using CGE editor, loaded from gamestatemain.castle-user-interface. }
    LabelFps:        TCastleLabel;
    LabelKeys:       TCastleLabel;
    LabelAction:     TCastleLabel;
    LabelFirstFrame: TCastleLabel;
	LabelBootStrap:  TCastleLabel;
    Viewport:        TCastleViewport;
    Scene:           TCastleScene;
    SecsPerRot:      Single;        // Complete one rotation in this many seconds
    ObjScale:        Single;        // Scale of objects making up the Sphere
    SavedTheta:      Single;        // Holds rotation angle if rotation paused
    SphereObjs:      Integer;       // Objects making up the Sphere
    RotateSphere:    Boolean;       // Is the Sphere Rotating
    CameraAtOrigin:  Boolean;       // Is Camera at (0, 0, 0)
    Models:          TModelArray;   // Models used to create the Sphere
	LoadTimer:		 Int64;			// Loading timer
    DoneBootstrap:   Boolean;       // To prevent mutiple bootstraps
    function    BuildSphere(const SomeModels: TModelArray; const ObjCount: Integer = 1): TX3DRootNode;
    procedure   LoadScene(const SomeModels: TModelArray; const ObjectsOnSphere: Integer = 1);
    procedure   SetCameraPosition;
    procedure   SaveTheta;
	procedure   BootStrap;
  public
    constructor Create(AOwner: TComponent); override;
    procedure   Start; override;
    procedure   Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
    function    Press(const Event: TInputPressRelease): Boolean; override;
  end;

var
  StateMain: TStateMain;

const
  ScaleMultiplier = 0.5;
  MinSphereObjs   = 64;
  ViewDistance    = 3;
  ModelFiles: Array [0..20] of String = ('Alien.glb','Alien_Tall.glb','Bat.glb',
			  'Bee.glb','Cactus.glb','Chicken.glb','Crab.glb','Cthulhu.glb',
			  'Cyclops.glb','Deer.glb','Demon.glb','Ghost.glb','GreenDemon.glb',
			  'Mushroom.glb','Panda.glb','Penguin.glb','Pig.glb','Skull.glb',
			  'Tree.glb','YellowDragon.glb','Yeti.glb');

implementation

uses SysUtils;

{ TCastleSceneHelper }

{ Normalize fits the model in a 1x1x1 cube and centers it }
function TCastleSceneHelper.Normalize: TVector3;
begin
  Result := TVector3.Zero;
  if not(Self = nil) then
    begin
    if not BoundingBox.IsEmptyOrZero then
      begin
        if BoundingBox.MaxSize > 0 then
          begin
            Result := BoundingBox.Size;
            Center := Vector3(Min(BoundingBox.Data[0].X, BoundingBox.Data[1].X) + (BoundingBox.SizeX / 2),
                              Min(BoundingBox.Data[0].Y, BoundingBox.Data[1].Y) + (BoundingBox.SizeY / 2),
                              Min(BoundingBox.Data[0].Z, BoundingBox.Data[1].Z) + (BoundingBox.SizeZ / 2));
            Scale := Vector3(1 / BoundingBox.MaxSize,
                             1 / BoundingBox.MaxSize,
                             1 / BoundingBox.MaxSize);

            Translation := -Center;
          end;
      end;
    end;
end;

function TCastleSceneHelper.IsVisible: Boolean;
begin
  Result := IsVisibleNow;
end;

{ TCastleViewportHelper }

{ ViewFromRadius sets the camera ARadius from (0,0,0)
  at AElevation pointing at (0,0,0) from ATheta radians
  around the Y-Axis}
procedure TCastleViewportHelper.ViewFromRadius(const ARadius: Single; const AElevation: Single; const ATheta: Single);
begin
    ViewFromRadius(ARadius, Vector3(sqrt(ARadius) * Cos(ATheta), AElevation, sqrt(ARadius) * Sin(ATheta)));
end;

{ ViewFromRadius sets the camera at ARadius pointing at (0,0,0)
  in ADirection on the Y-Axis}
procedure TCastleViewportHelper.ViewFromRadius(const ARadius: Single; const ADirection: TVector3);
begin
  Camera.Up := Vector3(0, 1, 0);
  Camera.Direction := -ADirection;
  Camera.Position  := ARadius * ADirection.Normalize;
end;

{ TStateMain ----------------------------------------------------------------- }

constructor TStateMain.Create(AOwner: TComponent);
var
  i: Integer;
begin
  inherited;
  DesignUrl := 'castle-data:/gamestatemain.castle-user-interface';
  SavedTheta := 0;
  SecsPerRot := 15;
  SphereObjs := 128;
  RotateSphere := True;
  CameraAtOrigin := False;
  LoadTimer := 0;
  DoneBootstrap := False;

  SetLength(Models, High(ModelFiles) + 1);
  for i := Low(Models) to High(Models) do
    begin
      Models[i] := LoadNode('castle-data:/AnimatedModels/' + ModelFiles[i]);
    end;
	
end;

procedure TStateMain.Start;
begin
  inherited;

  { Find components, by name, that we need to access from code }
  LabelFps := DesignedComponent('LabelFps') as TCastleLabel;
  LabelKeys := DesignedComponent('LabelKeys') as TCastleLabel;
  LabelAction := DesignedComponent('LabelAction') as TCastleLabel;
  LabelFirstFrame := DesignedComponent('LabelFirstFrame') as TCastleLabel;
  LabelBootStrap := DesignedComponent('LabelBootStrap') as TCastleLabel;
  Scene :=  DesignedComponent('Scene') as TCastleScene;
  Viewport :=  DesignedComponent('Viewport') as TCastleViewport;

  LabelAction.Caption := '';
  LabelFirstFrame.Caption := '';
  
  LabelKeys.Caption := 'Control Keys' + LineEnding +
    'D = Double Number of Objects' + LineEnding +
    'H = Halve Number of Objects' + LineEnding +
    'X = Toggle Control Display' + LineEnding +
    'R = Toggle Sphere Rotation' + LineEnding +
    'C = Position Camera Inside/Outside Sphere' + LineEnding +
    'G = Grab Screen (grab.png)' + LineEnding +
    '[ = Rotate Slower' + LineEnding +
    '] = Rotate Faster' + LineEnding +
    'ESC = Quit' + LineEnding;
  LabelKeys.Exists := False;

//    'S = Toggle Object Spin' + LineEnding + // Not yet...

end;

procedure TStateMain.BootStrap;
begin
  if not DoneBootstrap then
    begin
      LoadScene(Models, SphereObjs);
      DoneBootstrap := True;
      LabelKeys.Exists := True;
	  LabelBootStrap.Exists := False;
	end;
end;

procedure TStateMain.Update(const SecondsPassed: Single; var HandleInput: Boolean);
var
  CurrentTheta: Single;
begin
  inherited;
  { This virtual method is executed every frame.}
  LabelFps.Caption := 'FPS: ' + Container.Fps.ToString;

  if not (Scene = nil) and Scene.IsVisible then
    begin
	  if not(LoadTimer = 0) then
	    begin
		  LabelFirstFrame.Caption := 'Load Time = ' + FormatFloat('###0.000', (CastleGetTickCount64 - LoadTimer) / 1000) + ' seconds';
		  LoadTimer := 0;
		end;
      if RotateSphere then
        begin
          LabelAction.Caption := 'Sphere of ' + IntToStr(SphereObjs) + ' objects rotating once every ' + FormatFloat('#0.00', SecsPerRot) + ' seconds';
          // Set angle (theta) to revolve completely once every SecsPerRot
          CurrentTheta := (((CastleGetTickCount64 mod
                     (SecsPerRot * 1000)) /
                     (SecsPerRot * 1000)) * (Pi * 2)) + SavedTheta;

          // Rotate the scene in Y
          Scene.Rotation := Vector4(0, 1, 0, CurrentTheta);
        end
      else
        begin
          LabelAction.Caption := 'Sphere of ' + IntToStr(SphereObjs) + ' objects';
        end;

{
      if RotateObjects then
        begin
          ObjNode := Scene.RootNode.FindNodeByName(TGroupNode, 'SphereGroup', True) as TGroupNode;
          if not (ObjNode = nil) then
            begin
              ObjNode.EnumerateNodes(TTransformNode, @Spinner, True);
            end;
        end;
}
    end;

end;

function TStateMain.Press(const Event: TInputPressRelease): Boolean;
begin
  if Event.IsKey(keyEscape) then // Why didn't I use a switch?
    begin
      Application.Terminate;
    end
  else if Event.IsKey(keyX) then
    begin
      LabelKeys.Exists := not LabelKeys.Exists;
    end
  else if Event.IsKey(']') then
    begin
      if SecsPerRot > 0.25 then
        begin
          SaveTheta; // This don't work properly yet
          SecsPerRot := SecsPerRot - 0.25;
        end;
    end
  else if Event.IsKey('[') then
    begin
      SaveTheta; // This don't work properly yet
      SecsPerRot := SecsPerRot + 0.25;
    end
  else if Event.IsKey(keyD) then
    begin
      SphereObjs := SphereObjs * 2;
      // Show the load time, number of objects and scale
      LoadScene(Models, SphereObjs);
    end
  // Double number of objects
  else if Event.IsKey(keyH) then
    begin
      if SphereObjs >= MinSphereObjs then
        begin
          SphereObjs := SphereObjs div 2;
          // Show the load time, number of objects and scale
          LoadScene(Models, SphereObjs);
        end;
    end
  // Toggle Camera Position (0, 0, 0) / normal
  else if Event.IsKey(keyC) then
    begin
      // Switch CameraAtOrigin after saving settings!!!
      CameraAtOrigin := not CameraAtOrigin;
      SetCameraPosition;
    end
  else if Event.IsKey(keyR) then
    begin
      RotateSphere := Not RotateSphere;
      SaveTheta;
	end
  else if Event.IsKey(keyG) then
    begin
      Container.SaveScreen('grab.png');
	end
  else if Event.IsKey(keySpace) then
    begin
	  if not DoneBootstrap then
		begin
		  BootStrap;
		end;
    end;

  Result := inherited;
  if Result then Exit; // allow the ancestor to handle keys

  { This virtual method is executed when user presses
    a key, a mouse button, or touches a touch-screen.

    Note that each UI control has also events like OnPress and OnClick.
    These events can be used to handle the "press", if it should do something
    specific when used in that UI control.
    The TStateMain.Press method should be used to handle keys
    not handled in children controls.
  }

  // Use this to handle keys:
  {
  if Event.IsKey(keyXxx) then
  begin
    // DoSomething;
    Exit(true); // key was handled
  end;
  }
end;

procedure TStateMain.SaveTheta;
var
  CurrentTheta: Single;
begin
  // Only do anything with Scene if it's loaded
  if not (Scene = nil) then
    begin
      if RotateSphere then
        begin
          // If the scene is about to resume store an offset in SavedTheta
          CurrentTheta := ((CastleGetTickCount64 mod
                           (SecsPerRot * 1000)) /
                           (SecsPerRot * 1000)) * (Pi * 2);
          SavedTheta := SavedTheta - CurrentTheta;
        end
      else
        begin
          // Save the current rotation in SavedTheta
          SavedTheta := Scene.Rotation.W; // W is the angle of a Vector4
        end;
    end;
end;

procedure TStateMain.SetCameraPosition;
begin
  if CameraAtOrigin then
    begin
      Viewport.Camera.Position := Vector3(0, 0, 0);
    end
  else
    begin
      Viewport.ViewFromRadius(ViewDistance, 1, 0);
    end;
end;

function TStateMain.BuildSphere(const SomeModels: TModelArray; const ObjCount: Integer = 1): TX3DRootNode;
var
  GroupNode: TGroupNode;
  GridNode: TX3DRootNode;
  TransformNode: TTransformNode;
  NewGridNode: TX3DRootNode;
  XPos: Single;
  YPos: Single;
  ZPos: Single;
  Phi: Single;
  Theta: Single;
  Radius: Single;
  Idx: Integer;
  RandomModel: Integer;
  ObjRotation: TVector4;
begin
  // Create the required objects
  GroupNode := TGroupNode.Create;
  GroupNode.X3DName:='SphereGroup'; // Make it easy to find later
  GridNode := TX3DRootNode.Create;
  GridNode.AddChildren(GroupNode);

  // The scale of objects making up the Sphere is
  // the inverse square root of the number of objects
  // divided by 2 (Sphere is radius 1, objects are radius 0.5)
  // ScaleMultiplier allows fine tuning of object size
  ObjScale := (1 / (sqrt(ObjCount) / 2)) * ScaleMultiplier;

  // Fibonnaci Sphere from StackOverflow answer with Python code + screenshot
  // https://stackoverflow.com/questions/9600801/evenly-distributing-n-points-on-a-sphere

  // Golden angle in radians
  Phi := pi * (3 - sqrt(5));

  for Idx := 0 to ObjCount -1 do
    begin
      // Adapted from the StackOverflow code
      LabelAction.Caption := 'Building scene for ' + IntToStr(SphereObjs) + ' objects.' + LineEnding + 'Adding model ' + IntToStr(Idx + 1);
	  Application.ProcessAllMessages;
      YPos := 1 - (Idx / (ObjCount - 1)) * 2;
      Radius := sqrt(1 - (YPos * YPos));
      Theta := Phi * Idx;
      XPos := cos(Theta) * Radius;
      ZPos := sin(Theta) * Radius;
      // We not have X, Y and Z for the object so apply scale + translation
      TransformNode := TTransformNode.Create;
      TransformNode.Scale := Vector3(ObjScale, ObjScale, ObjScale);
      TransformNode.Translation := Vector3(XPos, YPos, ZPos);
      repeat // Avoid rotation axis of (0, 0, 0)
        ObjRotation :=  Vector4(random * 2 * Pi, random * 2 * Pi, random * 2 * Pi, random * 2 * Pi)
      until not((ObjRotation.X = 0) and (ObjRotation.Y = 0) and (ObjRotation.Z = 0));
      TransformNode.Rotation := ObjRotation;
      RandomModel := Random(Length(SomeModels));
      NewGridNode := SomeModels[RandomModel].DeepCopy as TX3DRootNode;
      TransformNode.AddChildren(NewGridNode);
      // Add the object + transform to the group
      GroupNode.AddChildren(TransformNode);
    end;

  LabelAction.Caption := 'Scene constructed for ' + IntToStr(SphereObjs) + ' objects.' + LineEnding + 
    'Elapsed time = ' + FormatFloat('###0.000', (CastleGetTickCount64 - LoadTimer) / 1000) + ' seconds' + LineEnding + 'CGE is doing other things ATM ... ';
  Application.ProcessAllMessages;

  // The group now contains ObjCount objects in a Spherical arrangement
  Result := GridNode;
end;

procedure TStateMain.LoadScene(const SomeModels: TModelArray; const ObjectsOnSphere: Integer = 1);
var
  SphereNode: TX3DRootNode;
begin
  if Assigned(Scene) then
    begin
      FreeAndNil(Scene);
      LoadTimer := CastleGetTickCount64;
    end;
  // Create a scene
  Scene := TCastleScene.Create(Self);

  {$ifdef usebatching}
  DynamicBatching := True;
  {$endif}

  // Load a model into the scene
  SphereNode := BuildSphere(Models, ObjectsOnSphere);
  Scene.Load(SphereNode, True);
//  Scene.Scale := Vector3(0.5, 0.5, 0.5);

  // Add the scene to the viewport
  Viewport.Items.Add(Scene);

  // Tell the control this is the main scene so it gets some lighting
  Viewport.Items.MainScene := Scene;
  
  SetCameraPosition;
end;


end.
