-- loom-go: Loom-like screen recorder for Hammerspoon
-- Records screen + webcam + audio with instant shareable URLs
-- Triggered by Cmd+Option+S

local screenRecorder = {}
screenRecorder.isRecording = false
screenRecorder.screenTask = nil
screenRecorder.audioTask = nil
screenRecorder.webcamTask = nil
screenRecorder.recordingFolder = nil

-- Configuration
local recordingDirectory = os.getenv("HOME") .. "/Desktop/ScreenRecordings"
local configFile = recordingDirectory .. "/.screen-go-config.json"
local recordFormat = "mp4"
local selectedScreenId = nil
local currentScreenName = "Main Display"
local availableScreens = {}
local selectedCameraDevice = nil
local currentCameraName = "No Camera"
local availableCameras = {}
local selectedAudioDevice = ":0"  -- Default audio input
local currentAudioName = "Built-in Microphone"
local availableAudioDevices = {}
local autoUpload = false
local gcsBucket = ""  -- Google Cloud Storage bucket name
local quickUrlEnabled = true  -- Beta: Get URL immediately by uploading placeholder first

-- Audio settings
local audioGain = 0.5  -- Audio gain multiplier (0.1 to 2.0, default 0.5 = 50% to prevent clipping)

-- Composite video settings
local webcamPosition = "bottom-right"  -- Options: bottom-left, bottom-right, top-left, top-right
local webcamSizePercent = 25  -- Webcam size as percentage of screen width (default: 25%)
local webcamPadding = 20  -- Padding from screen edges in pixels
local webcamCircleCrop = true  -- Crop webcam to circle in composite

-- Preview overlay reference
local previewOverlay = nil
local screenPreviewOverlay = nil

-- Show webcam size preview on screen
local function showWebcamPreview(sizePercent, autoDismiss)
    if autoDismiss == nil then autoDismiss = true end
    
    -- Remove any existing preview
    if previewOverlay then
        previewOverlay:delete()
        previewOverlay = nil
    end
    
    if sizePercent == 0 then
        -- Show "Off" message
        hs.alert.show("📷 Webcam: Off", 2)
        return
    end
    
    local screen = hs.screen.mainScreen()
    local frame = screen:fullFrame()
    
    -- Calculate webcam size
    local webcamWidth = math.floor(frame.w * (sizePercent / 100))
    local webcamHeight = webcamWidth  -- Square for circle
    
    -- Calculate position based on webcamPosition
    local x, y
    if webcamPosition == "bottom-right" then
        x = frame.x + frame.w - webcamWidth - webcamPadding
        y = frame.y + frame.h - webcamHeight - webcamPadding
    elseif webcamPosition == "bottom-left" then
        x = frame.x + webcamPadding
        y = frame.y + frame.h - webcamHeight - webcamPadding
    elseif webcamPosition == "top-right" then
        x = frame.x + frame.w - webcamWidth - webcamPadding
        y = frame.y + webcamPadding
    else -- top-left
        x = frame.x + webcamPadding
        y = frame.y + webcamPadding
    end
    
    -- Create semi-transparent circle overlay
    previewOverlay = hs.canvas.new({x = x, y = y, w = webcamWidth, h = webcamHeight})
    previewOverlay:insertElement({
        type = "circle",
        action = "strokeAndFill",
        strokeColor = {red = 0.4, green = 0.5, blue = 0.9, alpha = 0.8},
        fillColor = {red = 0.4, green = 0.5, blue = 0.9, alpha = 0.2},
        strokeWidth = 4,
        frame = {x = "0%", y = "0%", w = "100%", h = "100%"}
    })
    previewOverlay:insertElement({
        type = "text",
        text = sizePercent .. "%",
        textSize = webcamWidth / 5,
        textColor = {white = 1, alpha = 0.9},
        textAlignment = "center",
        frame = {x = "0%", y = "40%", w = "100%", h = "20%"}
    })
    previewOverlay:show()
    
    -- Auto-hide after 2 seconds (if autoDismiss is true)
    if autoDismiss then
        hs.timer.doAfter(2, function()
            if previewOverlay then
                previewOverlay:delete()
                previewOverlay = nil
            end
        end)
    end
end

-- Dismiss webcam preview manually
local function dismissWebcamPreview()
    if previewOverlay then
        previewOverlay:delete()
        previewOverlay = nil
    end
end

-- Show screen selection border preview
local function showScreenPreview(screenId, autoDismiss)
    if autoDismiss == nil then autoDismiss = true end
    
    -- Remove any existing preview
    if screenPreviewOverlay then
        screenPreviewOverlay:delete()
        screenPreviewOverlay = nil
    end
    
    -- Find the screen object
    local screen = nil
    for _, s in ipairs(availableScreens) do
        if s.id == screenId then
            screen = s
            break
        end
    end
    
    if not screen then
        print("ERROR: Screen not found for preview")
        return
    end
    
    -- Get the screen's frame
    local hsScreen = hs.screen.find(screen.id)
    if not hsScreen then
        print("ERROR: Could not find Hammerspoon screen object")
        return
    end
    
    local frame = hsScreen:fullFrame()
    
    -- Create border overlay with thick colored border
    screenPreviewOverlay = hs.canvas.new(frame)
    
    -- Add border rectangle
    local borderWidth = 10
    screenPreviewOverlay:insertElement({
        type = "rectangle",
        action = "stroke",
        strokeColor = {red = 0.2, green = 0.8, blue = 0.3, alpha = 0.9},
        strokeWidth = borderWidth,
        frame = {x = 0, y = 0, w = frame.w, h = frame.h}
    })
    
    -- Add screen name at top center
    screenPreviewOverlay:insertElement({
        type = "rectangle",
        action = "fill",
        fillColor = {red = 0.2, green = 0.8, blue = 0.3, alpha = 0.8},
        frame = {x = (frame.w / 2) - 150, y = 20, w = 300, h = 50}
    })
    
    screenPreviewOverlay:insertElement({
        type = "text",
        text = screen.name,
        textSize = 24,
        textColor = {white = 1, alpha = 1},
        textAlignment = "center",
        frame = {x = (frame.w / 2) - 150, y = 25, w = 300, h = 40}
    })
    
    screenPreviewOverlay:show()
    
    -- Auto-hide after 2 seconds (if autoDismiss is true)
    if autoDismiss then
        hs.timer.doAfter(2, function()
            if screenPreviewOverlay then
                screenPreviewOverlay:delete()
                screenPreviewOverlay = nil
            end
        end)
    end
end

-- Dismiss screen preview manually
local function dismissScreenPreview()
    if screenPreviewOverlay then
        screenPreviewOverlay:delete()
        screenPreviewOverlay = nil
    end
end

-- Load configuration from file
local function loadConfig()
    local file = io.open(configFile, "r")
    if file then
        local content = file:read("*all")
        file:close()
        
        local success, config = pcall(function()
            return hs.json.decode(content)
        end)
        
        if success and config then
            gcsBucket = config.gcsBucket or ""
            autoUpload = config.autoUpload or false
            quickUrlEnabled = config.quickUrlEnabled ~= false  -- Default true
            audioGain = config.audioGain or 0.5  -- Default 50% to prevent clipping
            webcamPosition = config.webcamPosition or "bottom-right"
            webcamSizePercent = config.webcamSizePercent or 25
            webcamCircleCrop = config.webcamCircleCrop ~= false  -- Default true
            selectedCameraDevice = config.selectedCameraDevice  -- Can be nil
            selectedAudioDevice = config.selectedAudioDevice or ":0"
            
            -- If bucket is configured but autoUpload is false, enable it
            if gcsBucket ~= "" and not autoUpload then
                autoUpload = true
                print("Auto-enabled upload for configured bucket")
            end
            
            print("Loaded config: bucket=" .. gcsBucket .. ", autoUpload=" .. tostring(autoUpload) .. ", quickUrl=" .. tostring(quickUrlEnabled) .. ", audioGain=" .. audioGain)
            return true
        end
    end
    
    print("No config file found, using defaults")
    return false
end

-- Save configuration to file
local function saveConfig()
    local config = {
        gcsBucket = gcsBucket,
        autoUpload = autoUpload,
        quickUrlEnabled = quickUrlEnabled,
        audioGain = audioGain,
        webcamPosition = webcamPosition,
        webcamSizePercent = webcamSizePercent,
        webcamCircleCrop = webcamCircleCrop,
        selectedCameraDevice = selectedCameraDevice,
        selectedAudioDevice = selectedAudioDevice
    }
    
    local content = hs.json.encode(config)
    local file = io.open(configFile, "w")
    if file then
        file:write(content)
        file:close()
        print("Config saved")
        return true
    else
        print("Failed to save config")
        return false
    end
end

-- Find ffmpeg path
local function findFFmpegPath()
    local paths = {
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    }
    
    for _, path in ipairs(paths) do
        local check = hs.execute("test -f '" .. path .. "' && echo 'found' || echo 'notfound'")
        if check and check:match("found") then
            print("Found ffmpeg at: " .. path)
            return path
        end
    end
    
    -- Try using 'which' command
    local whichOutput = hs.execute("which ffmpeg 2>&1")
    if whichOutput and not whichOutput:match("not found") then
        local path = whichOutput:match("^%s*(.-)%s*$")  -- trim whitespace
        if path and path ~= "" then
            print("Found ffmpeg via 'which' at: " .. path)
            return path
        end
    end
    
    print("ERROR: Could not find ffmpeg!")
    return "/opt/homebrew/bin/ffmpeg"  -- default fallback
end

-- Find gsutil path
local function findGsutilPath()
    local paths = {
        "/opt/homebrew/bin/gsutil",
        "/usr/local/bin/gsutil",
        "/usr/bin/gsutil"
    }
    
    for _, path in ipairs(paths) do
        local check = hs.execute("test -f '" .. path .. "' && echo 'found' || echo 'notfound'")
        if check and check:match("found") then
            print("Found gsutil at: " .. path)
            return path
        end
    end
    
    print("WARNING: Could not find gsutil!")
    return "/opt/homebrew/bin/gsutil"  -- default fallback
end

local ffmpegPath = findFFmpegPath()
local gsutilPath = findGsutilPath()

-- Menu bar
local menuBar = nil

-- Utility: Trim whitespace
function string:trim()
    return self:match("^%s*(.-)%s*$")
end

-- Ensure recording directory exists
function screenRecorder.ensureDirectory()
    local dir = recordingDirectory
    os.execute("mkdir -p '" .. dir .. "'")
end

-- Enumerate available screens
function screenRecorder.enumerateScreens()
    availableScreens = {}
    local screens = hs.screen.allScreens()
    
    for i, screen in ipairs(screens) do
        local screenName = screen:name() or ("Display " .. i)
        table.insert(availableScreens, {
            id = screen:id(),
            name = screenName,
            screen = screen
        })
    end
    
    if #availableScreens > 0 and not selectedScreenId then
        selectedScreenId = availableScreens[1].id
        currentScreenName = availableScreens[1].name
    end
    
    return availableScreens
end

-- Enumerate available cameras and audio devices using FFmpeg
function screenRecorder.enumerateCameras()
    print("\n=== STARTING DEVICE ENUMERATION ===")
    availableCameras = {}
    availableAudioDevices = {}
    
    print("FFmpeg path: " .. ffmpegPath)
    print("Checking if ffmpeg exists...")
    local checkCmd = "test -f " .. ffmpegPath .. " && echo 'EXISTS' || echo 'NOT FOUND'"
    local checkResult = hs.execute(checkCmd)
    print("FFmpeg check result: " .. checkResult)
    
    -- Run FFmpeg synchronously to list devices
    print("Running ffmpeg to list devices...")
    local output = hs.execute(ffmpegPath .. ' -f avfoundation -list_devices true -i "" 2>&1')
    
    if not output then
        print("ERROR: No output from ffmpeg!")
        return availableCameras
    end
    
    print("FFmpeg output received, length: " .. #output)
    print("=== FFmpeg Raw Output START ===")
    print(output)
    print("=== FFmpeg Raw Output END ===")
    
    local inVideoSection = false
    local inAudioSection = false
    local lineCount = 0
    
    for line in output:gmatch("[^\r\n]+") do
        lineCount = lineCount + 1
        
        -- Detect section headers
        if line:match("AVFoundation video devices:") then
            inVideoSection = true
            inAudioSection = false
            print(">>> FOUND VIDEO SECTION HEADER at line " .. lineCount)
        elseif line:match("AVFoundation audio devices:") then
            inVideoSection = false
            inAudioSection = true
            print(">>> FOUND AUDIO SECTION HEADER at line " .. lineCount)
        elseif inAudioSection and not line:match("%[AVFoundation") then
            print(">>> END OF AUDIO SECTION at line " .. lineCount)
            break
        end
        
        -- Parse device lines - format: [AVFoundation indev @ 0x...] [0] Device Name
        if line:match("%[AVFoundation") and line:match("%]") then
            local deviceNum, deviceName = line:match("%[(%d+)%] (.+)")
            if deviceNum and deviceName then
                print(">>> Parsed device: num=" .. deviceNum .. " name=" .. deviceName .. " inVideo=" .. tostring(inVideoSection) .. " inAudio=" .. tostring(inAudioSection))
                
                if inVideoSection then
                    -- Skip "Capture screen" entries
                    if not deviceName:match("Capture screen") then
                        print("    ✓ Adding VIDEO device [" .. deviceNum .. "] " .. deviceName)
                        table.insert(availableCameras, {
                            index = deviceNum,
                            name = deviceName
                        })
                    else
                        print("    ✗ Skipping Capture screen device")
                    end
                elseif inAudioSection then
                    print("    ✓ Adding AUDIO device [" .. deviceNum .. "] " .. deviceName)
                    table.insert(availableAudioDevices, {
                        index = deviceNum,
                        name = deviceName
                    })
                end
            else
                print(">>> Failed to parse line: " .. line)
            end
        end
    end
    
    print("\n=== ENUMERATION COMPLETE ===")
    print("Total lines processed: " .. lineCount)
    print("Cameras found: " .. #availableCameras)
    for i, cam in ipairs(availableCameras) do
        print("  Camera " .. i .. ": [" .. tostring(cam.index) .. "] " .. cam.name)
    end
    print("Audio devices found: " .. #availableAudioDevices)
    for i, aud in ipairs(availableAudioDevices) do
        print("  Audio " .. i .. ": [" .. tostring(aud.index) .. "] " .. aud.name)
    end
    print("==============================\n")
    
    -- Add "No Camera" option if no cameras found
    if #availableCameras == 0 then
        print("No cameras found, adding 'No Camera' option")
        table.insert(availableCameras, {index = nil, name = "No Camera"})
    end
    
    -- Set default camera (first available real camera)
    if not selectedCameraDevice and #availableCameras > 0 then
        -- Find first camera that's not nil
        for _, cam in ipairs(availableCameras) do
            if cam.index ~= nil then
                selectedCameraDevice = cam.index
                currentCameraName = cam.name
                print("Set default camera: [" .. tostring(selectedCameraDevice) .. "] " .. currentCameraName)
                break
            end
        end
    end
    
    return availableCameras
end

-- Enumerate available audio devices
function screenRecorder.enumerateAudioDevices()
    -- Audio devices are populated during camera enumeration
    -- Just set defaults if needed
    if #availableAudioDevices == 0 then
        print("Warning: No audio devices detected")
        table.insert(availableAudioDevices, {index = "1", name = "Built-in Microphone"})
    end
    
    -- Set default audio device
    if not selectedAudioDevice and #availableAudioDevices > 0 then
        selectedAudioDevice = ":" .. availableAudioDevices[1].index
        currentAudioName = availableAudioDevices[1].name
        print("Default audio device set to: " .. currentAudioName)
    end
    
    return availableAudioDevices
end

-- Start recording
function screenRecorder.startRecording()
    if screenRecorder.isRecording then
        hs.alert.show("⏺️ Already recording")
        return
    end
    
    print("\n=== STARTING RECORDING ===")
    screenRecorder.ensureDirectory()
    
    -- Create timestamped folder
    local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
    screenRecorder.recordingFolder = recordingDirectory .. "/recording_" .. timestamp
    os.execute("mkdir -p '" .. screenRecorder.recordingFolder .. "'")
    print("Recording folder: " .. screenRecorder.recordingFolder)
    
    local screenFile = screenRecorder.recordingFolder .. "/screen." .. recordFormat
    local audioFile = screenRecorder.recordingFolder .. "/audio.wav"  -- Separate audio file
    local webcamFile = screenRecorder.recordingFolder .. "/webcam." .. recordFormat
    
    print("Screen output: " .. screenFile)
    print("Audio output: " .. audioFile)
    print("Webcam output: " .. webcamFile)
    
    -- Get screen dimensions for recording
    local screen = hs.screen.find(selectedScreenId)
    if not screen then
        screen = hs.screen.mainScreen()
    end
    
    local frame = screen:fullFrame()
    local width = math.floor(frame.w)
    local height = math.floor(frame.h)
    
    print("Screen dimensions: " .. width .. "x" .. height)
    
    -- Start screen recording with FFmpeg
    -- For screen recording on macOS, we need to use the "Capture screen X" device
    -- These are offset by the number of camera devices (typically starting at index 3+)
    -- Screen 0 = Capture screen 0 (device index starts after cameras)
    local screenIndex = 0
    for i, scr in ipairs(availableScreens) do
        if scr.id == selectedScreenId then
            screenIndex = i - 1  -- 0-based indexing for screens
            break
        end
    end
    
    -- Adjust screen index: add offset for camera devices
    -- Typically: 0-2 are cameras, 3+ are "Capture screen X"
    local screenCaptureIndex = screenIndex + #availableCameras
    
    print("Screen index: " .. screenIndex)
    print("Screen capture device index: " .. screenCaptureIndex)
    print("Audio device: " .. selectedAudioDevice)
    
    -- Record screen VIDEO ONLY (no audio) to avoid AVFoundation audio distortion
    local screenArgs = {
        "-f", "avfoundation",
        "-framerate", "30",
        "-capture_cursor", "1",
        "-capture_mouse_clicks", "1",
        "-i", tostring(screenCaptureIndex) .. ":none",  -- NO AUDIO
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-tune", "zerolatency",
        "-crf", "23",
        "-pix_fmt", "yuv420p",
        "-y",
        screenFile
    }
    
    print("Screen recording command (VIDEO ONLY): " .. ffmpegPath .. " " .. table.concat(screenArgs, " "))
    print("Screen recording output file: " .. screenFile)
    
    -- Verify output directory exists and is writable
    local dirCheck = hs.execute("test -d '" .. screenRecorder.recordingFolder .. "' && test -w '" .. screenRecorder.recordingFolder .. "' && echo 'OK' || echo 'FAIL'")
    print("Output directory check: " .. dirCheck:trim())
    
    screenRecorder.screenTask = hs.task.new(ffmpegPath, 
        function(exitCode, stdOut, stdErr)
            print("🔴 Screen recording stopped with exit code: " .. tostring(exitCode))
            if stdOut and stdOut ~= "" then
                print("Screen recording stdout: " .. stdOut)
            end
            if stdErr and stdErr ~= "" then
                print("Screen recording stderr: " .. stdErr)
            end
        end,
        screenArgs
    )
    
    -- Set streaming callback to capture errors in real-time
    screenRecorder.screenTask:setStreamingCallback(function(task, stdOut, stdErr)
        if stdOut and stdOut ~= "" then
            print("⚠️ Screen stdout: " .. stdOut)
        end
        if stdErr and stdErr ~= "" then
            print("⚠️ Screen stderr: " .. stdErr)
        end
        return true
    end)
    
    -- Start AUDIO recording with SOX (clean audio, no distortion)
    local audioDeviceIndex = selectedAudioDevice:match(":(%d+)") or "0"
    
    local audioArgs = {
        "-c", "2",  -- Stereo
        "-r", "48000",  -- 48kHz sample rate
        "-b", "16",  -- 16-bit
        audioFile
    }
    
    print("Audio recording command (SOX): rec " .. table.concat(audioArgs, " "))
    print("Audio device: [" .. audioDeviceIndex .. "] " .. currentAudioName)
    
    screenRecorder.audioTask = hs.task.new("/opt/homebrew/bin/rec",
        function(exitCode, stdOut, stdErr)
            print("Audio recording stopped with exit code: " .. exitCode)
            if stdOut and stdOut ~= "" then
                print("Audio recording stdout: " .. stdOut)
            end
            if stdErr and stdErr ~= "" then
                print("Audio recording stderr: " .. stdErr)
            end
        end,
        audioArgs
    )
    
    -- Set streaming callback to capture errors in real-time
    screenRecorder.audioTask:setStreamingCallback(function(task, stdOut, stdErr)
        if stdErr and stdErr ~= "" then
            print("⚠️ Audio recording: " .. stdErr)
        end
        return true
    end)
    
    -- Setup webcam recording if camera is selected
    local webcamTask = nil
    if selectedCameraDevice and selectedCameraDevice ~= "nil" then
        print("Starting webcam recording with device: " .. selectedCameraDevice)
        
        local webcamArgs = {
            "-f", "avfoundation",
            "-framerate", "30",
            "-video_size", "1280x720",
            "-i", selectedCameraDevice .. ":",
            "-c:v", "libx264",
            "-preset", "ultrafast",
            "-crf", "23",
            "-pix_fmt", "yuv420p",
            "-y",  -- Overwrite output files
            webcamFile
        }
        
        print("Webcam recording command: " .. ffmpegPath .. " " .. table.concat(webcamArgs, " "))
        
        screenRecorder.webcamTask = hs.task.new(ffmpegPath,
            function(exitCode, stdOut, stdErr)
                print("Webcam recording stopped with exit code: " .. exitCode)
                if stdOut and stdOut ~= "" then
                    print("Webcam recording stdout: " .. stdOut)
                end
                if stdErr and stdErr ~= "" then
                    print("Webcam recording stderr: " .. stdErr)
                end
            end,
            webcamArgs
        )
        
        -- Set streaming callback to capture errors in real-time
        screenRecorder.webcamTask:setStreamingCallback(function(task, stdOut, stdErr)
            if stdErr and stdErr ~= "" then
                print("⚠️ Webcam recording: " .. stdErr)
            end
            return true
        end)
    else
        print("No webcam selected, skipping webcam recording")
    end
    
    -- COUNTDOWN before starting all tasks simultaneously
    print("\n⏺️ STARTING COUNTDOWN...")
    
    -- Show visual previews during countdown
    showScreenPreview(selectedScreenId, false)  -- Don't auto-dismiss
    if webcamSizePercent > 0 then
        showWebcamPreview(webcamSizePercent, false)  -- Don't auto-dismiss
    end
    
    hs.alert.show("⏺️ Recording in 3...")
    
    hs.timer.doAfter(1, function()
        hs.alert.show("⏺️ Recording in 2...")
        
        hs.timer.doAfter(1, function()
            hs.alert.show("⏺️ Recording in 1...")
            
            hs.timer.doAfter(1, function()
                -- Dismiss previews before recording starts
                dismissScreenPreview()
                dismissWebcamPreview()
                
                -- START ALL TASKS SIMULTANEOUSLY for perfect sync
                print("\n⏺️ STARTING ALL RECORDINGS SIMULTANEOUSLY...")
                local screenStarted = screenRecorder.screenTask:start()
                local audioStarted = screenRecorder.audioTask:start()
                print("Screen task started: " .. tostring(screenStarted))
                print("Audio task started: " .. tostring(audioStarted))
                
                -- Get PIDs immediately after starting
                if screenStarted and screenRecorder.screenTask then
                    local screenPid = screenRecorder.screenTask:pid()
                    print("Screen task PID: " .. tostring(screenPid))
                    if not screenPid or screenPid == 0 then
                        print("❌ WARNING: Screen task has invalid PID!")
                    end
                end
                
                local webcamStarted = true
                if screenRecorder.webcamTask then
                    webcamStarted = screenRecorder.webcamTask:start()
                    print("Webcam task started: " .. tostring(webcamStarted))
                end
                
                -- Verify ALL tasks started successfully
                if not screenStarted or not audioStarted or not webcamStarted then
                    print("❌ ERROR: Failed to start one or more recording tasks!")
                    print("  Screen: " .. tostring(screenStarted))
                    print("  Audio: " .. tostring(audioStarted))
                    print("  Webcam: " .. tostring(webcamStarted))
                    
                    -- Clean up any tasks that did start
                    if screenRecorder.screenTask then screenRecorder.screenTask:interrupt() end
                    if screenRecorder.audioTask then screenRecorder.audioTask:interrupt() end
                    if screenRecorder.webcamTask then screenRecorder.webcamTask:interrupt() end
                    
                    screenRecorder.screenTask = nil
                    screenRecorder.audioTask = nil
                    screenRecorder.webcamTask = nil
                    
                    hs.alert.show("❌ Recording failed to start - check console")
                    screenRecorder.updateMenuBar()
                    return
                end
                
                -- Double-check tasks are actually running after 1 second
                hs.timer.doAfter(1, function()
                    local screenRunning = screenRecorder.screenTask and screenRecorder.screenTask:isRunning()
                    local audioRunning = screenRecorder.audioTask and screenRecorder.audioTask:isRunning()
                    local webcamRunning = not screenRecorder.webcamTask or screenRecorder.webcamTask:isRunning()
                    
                    print("\n=== RECORDING STATUS CHECK (1s after start) ===")
                    print("Screen task running: " .. tostring(screenRunning))
                    print("Audio task running: " .. tostring(audioRunning))
                    print("Webcam task running: " .. tostring(webcamRunning))
                    
                    if not screenRunning or not audioRunning or not webcamRunning then
                        print("❌ ERROR: One or more tasks died after starting!")
                        print("  This usually means:")
                        print("  - Screen Recording permission not granted")
                        print("  - Camera/Microphone permission not granted")
                        print("  - FFmpeg or sox crashed")
                        print("  Check Hammerspoon Console for error messages above")
                        
                        -- Stop everything
                        if screenRecorder.isRecording then
                            screenRecorder.stopRecording()
                        end
                        
                        hs.alert.show("❌ Recording failed - check console for errors")
                    else
                        print("✅ All tasks confirmed running")
                    end
                    print("==============================================\n")
                end)
                
                screenRecorder.isRecording = true
                hs.alert.show("⏺️ RECORDING!")
                print("=== RECORDING IN PROGRESS ===\n")
                screenRecorder.updateMenuBar()
                
                -- Upload HTML placeholder in BACKGROUND AFTER recording has started
                if quickUrlEnabled and gcsBucket ~= "" and autoUpload then
                    -- Extract folder name from the existing recording folder path
                    local folderName = screenRecorder.recordingFolder:match("([^/]+)$")
                    local compositeUrl = string.format(
                        "https://storage.googleapis.com/%s/%s/composite.%s",
                        gcsBucket, folderName, recordFormat
                    )
                    
                    hs.timer.doAfter(1, function()  -- Wait 1 sec after recording starts
                        print("\n⚡ UPLOADING PLACEHOLDER...")
                        
                        -- Create HTML placeholder
                        local placeholderFile = screenRecorder.recordingFolder .. "/placeholder.html"
                        local placeholderContent = [[<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Video Processing...</title>
    <style>
        body {
            margin: 0;
            padding: 0;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        }
        .container {
            text-align: center;
            padding: 40px;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            max-width: 500px;
        }
        h1 { color: #333; margin: 0 0 20px 0; font-size: 28px; }
        p { color: #666; line-height: 1.6; font-size: 16px; margin: 15px 0; }
        .spinner {
            width: 50px;
            height: 50px;
            margin: 30px auto;
            border: 5px solid #f3f3f3;
            border-top: 5px solid #667eea;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .reload-btn {
            margin-top: 30px;
            padding: 12px 30px;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 16px;
            cursor: pointer;
            transition: background 0.3s;
        }
        .reload-btn:hover { background: #5568d3; }
    </style>
    <script>
        setTimeout(function() { location.reload(); }, 5000);
    </script>
</head>
<body>
    <div class="container">
        <div class="spinner"></div>
        <h1>🎬 Video Processing</h1>
        <p>Your recording is being uploaded...</p>
        <p><strong>This page will auto-refresh</strong> when the video is ready.</p>
        <p style="font-size: 14px; color: #999;">Or click the button below to reload manually.</p>
        <button class="reload-btn" onclick="location.reload()">Reload Now</button>
    </div>
</body>
</html>]]
                        
                        local ph = io.open(placeholderFile, "w")
                        if ph then
                            ph:write(placeholderContent)
                            ph:close()
                            
                            -- Upload placeholder asynchronously
                            local placeholderCmd = string.format(
                                "%s -h 'Content-Type:text/html' -h 'Cache-Control:no-cache, no-store, must-revalidate' cp '%s' 'gs://%s/%s/composite.%s' && %s acl ch -u AllUsers:R 'gs://%s/%s/composite.%s'",
                                gsutilPath, placeholderFile, gcsBucket, folderName, recordFormat,
                                gsutilPath, gcsBucket, folderName, recordFormat
                            )
                            
                            hs.task.new("/bin/sh", function(exitCode, stdout, stderr)
                                print("Placeholder uploaded (exit: " .. exitCode .. ")")
                                if exitCode == 0 then
                                    -- Copy URL to clipboard once placeholder is up
                                    hs.pasteboard.setContents(compositeUrl)
                                    print("✅ URL in clipboard: " .. compositeUrl)
                                else
                                    print("Placeholder upload error: " .. stderr)
                                end
                                os.remove(placeholderFile)
                            end, {"-c", placeholderCmd}):start()
                        end
                    end)
                end
            end)
        end)
    end)
    
    screenRecorder.updateMenuBar()
end

-- Stop recording
function screenRecorder.stopRecording()
    if not screenRecorder.isRecording then
        hs.alert.show("⏹️ Not recording")
        return
    end
    
    print("\n=== STOPPING RECORDING ===")
    
    -- Stop ALL tasks SIMULTANEOUSLY at the exact same time
    print("Stopping all recordings simultaneously...")
    
    local tasksToStop = {}
    
    if screenRecorder.screenTask then
        table.insert(tasksToStop, {task = screenRecorder.screenTask, name = "screen"})
    end
    
    if screenRecorder.audioTask then
        table.insert(tasksToStop, {task = screenRecorder.audioTask, name = "audio"})
    end
    
    if screenRecorder.webcamTask then
        table.insert(tasksToStop, {task = screenRecorder.webcamTask, name = "webcam"})
    end
    
    -- Send stop signals to ALL tasks at once for perfect sync
    -- Screen recording needs gentle stop to finalize MP4 properly
    for _, taskInfo in ipairs(tasksToStop) do
        local pid = taskInfo.task:pid()
        if taskInfo.name == "screen" then
            print("Sending SIGTERM to screen recording task (PID: " .. tostring(pid) .. ") for graceful stop...")
            if pid then
                os.execute("kill -15 " .. pid)  -- SIGTERM instead of SIGKILL
            end
        else
            print("Sending SIGINT to " .. taskInfo.name .. " recording task (PID: " .. tostring(pid) .. ")...")
            taskInfo.task:interrupt()
        end
    end
    
    -- Wait longer for screen FFmpeg to finalize the MP4 file properly
    hs.timer.doAfter(3, function()
        if screenRecorder.audioTask and screenRecorder.audioTask:isRunning() then
            print("⚠️ Audio task still running after 3s, force killing...")
            local pid = screenRecorder.audioTask:pid()
            if pid then
                os.execute("kill -9 " .. pid)
            end
        end
        if screenRecorder.webcamTask and screenRecorder.webcamTask:isRunning() then
            print("⚠️ Webcam task still running after 3s, force killing...")
            local pid = screenRecorder.webcamTask:pid()
            if pid then
                os.execute("kill -9 " .. pid)
            end
        end
        if screenRecorder.screenTask and screenRecorder.screenTask:isRunning() then
            print("⚠️ Screen task still running after 3s, force killing (will corrupt file)...")
            local pid = screenRecorder.screenTask:pid()
            if pid then
                os.execute("kill -9 " .. pid)
            end
        end
        print("All recording tasks stopped.")
    end)
    
    -- Clear task references
    screenRecorder.screenTask = nil
    screenRecorder.audioTask = nil
    screenRecorder.webcamTask = nil
    
    screenRecorder.isRecording = false
    hs.alert.show("⏹️ Processing... URL in clipboard")
    
    print("Waiting for FFmpeg to finalize files...")
    
    -- Wait for files to finish writing (10 seconds - MP4 finalization takes time)
    hs.timer.doAfter(10, function()
        print("\n=== MUXING AUDIO + VIDEO ===")
        local screenVideoFile = screenRecorder.recordingFolder .. "/screen_video_only.mp4"
        local audioFile = screenRecorder.recordingFolder .. "/audio.wav"
        local screenFile = screenRecorder.recordingFolder .. "/screen." .. recordFormat
        local webcamFile = screenRecorder.recordingFolder .. "/webcam." .. recordFormat
        
        -- Check if screen.mp4 exists BEFORE trying to rename it
        print("Checking for screen file: " .. screenFile)
        local screenFileExists = hs.execute("test -f '" .. screenFile .. "' && echo 'YES' || echo 'NO'")
        print("Screen file exists before rename: " .. screenFileExists:trim())
        
        if screenFileExists:trim() == "YES" then
            local screenFileSize = hs.execute("ls -lh '" .. screenFile .. "' 2>&1")
            print("Screen file details: " .. screenFileSize:trim())
        else
            print("❌ Screen file was never created by FFmpeg!")
            print("Listing all files in recording folder:")
            local allFiles = hs.execute("ls -lha '" .. screenRecorder.recordingFolder .. "/' 2>&1")
            print(allFiles)
        end
        
        -- Rename the video-only file (only if it exists)
        if screenFileExists:trim() == "YES" then
            local mvResult = os.execute("mv '" .. screenFile .. "' '" .. screenVideoFile .. "' 2>&1")
            print("Rename result: " .. tostring(mvResult))
        end
        
        -- Keep raw audio for debugging
        local rawWavBackup = screenRecorder.recordingFolder .. "/audio_raw.wav"
        os.execute("cp '" .. audioFile .. "' '" .. rawWavBackup .. "' 2>&1")
        print("Saved audio_raw.wav for debugging")
        
        -- Get durations to calculate offset
        local videoDurationStr = hs.execute(string.format("%s -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 '%s'", ffmpegPath, screenVideoFile))
        local audioDurationStr = hs.execute(string.format("%s -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 '%s'", ffmpegPath, audioFile))
        
        local videoDuration = tonumber(videoDurationStr:trim()) or 0
        local audioDuration = tonumber(audioDurationStr:trim()) or 0
        
        print("Video duration: " .. videoDuration .. "s")
        print("Audio duration: " .. audioDuration .. "s")
        
        local offset = audioDuration - videoDuration
        print("Duration difference: " .. offset .. "s")
        
        -- ALWAYS trim to match durations for perfect sync
        local muxCmd
        if math.abs(offset) > 0.05 then  -- Only trim if difference is > 50ms (noticeable)
            if offset > 0 then
                -- Audio is longer - audio started earlier - trim beginning of audio
                local audioTrimmed = screenRecorder.recordingFolder .. "/audio_trimmed.wav"
                local trimCmd = string.format(
                    "%s -i '%s' -ss %.3f -c copy -y '%s'",
                    ffmpegPath, audioFile, offset, audioTrimmed
                )
                print("Trimming audio start by " .. offset .. "s to sync: " .. trimCmd)
                hs.execute(trimCmd .. " 2>&1")
                
                -- Mux with trimmed audio
                muxCmd = string.format(
                    "%s -i '%s' -i '%s' -c:v copy -c:a aac_at -b:a 320k -map 0:v:0 -map 1:a:0 -shortest -y '%s'",
                    ffmpegPath, screenVideoFile, audioTrimmed, screenFile
                )
            else
                -- Video is longer - video started earlier - trim beginning of video
                local videoTrimmed = screenRecorder.recordingFolder .. "/video_trimmed.mp4"
                local trimOffset = math.abs(offset)
                local trimCmd = string.format(
                    "%s -i '%s' -ss %.3f -c copy -y '%s'",
                    ffmpegPath, screenVideoFile, trimOffset, videoTrimmed
                )
                print("Trimming video start by " .. trimOffset .. "s to sync: " .. trimCmd)
                hs.execute(trimCmd .. " 2>&1")
                
                -- Mux with trimmed video
                muxCmd = string.format(
                    "%s -i '%s' -i '%s' -c:v copy -c:a aac_at -b:a 320k -map 0:v:0 -map 1:a:0 -shortest -y '%s'",
                    ffmpegPath, videoTrimmed, audioFile, screenFile
                )
                
                -- Clean up trimmed video after mux
                os.execute("sleep 1 && rm '" .. videoTrimmed .. "' 2>&1 &")
            end
            
            -- Clean up trimmed audio if it was created
            os.execute("sleep 1 && rm -f '" .. screenRecorder.recordingFolder .. "/audio_trimmed.wav' 2>&1 &")
        else
            -- Normal mux
            muxCmd = string.format(
                "%s -i '%s' -i '%s' -c:v copy -c:a aac_at -b:a 320k -map 0:v:0 -map 1:a:0 -shortest -y '%s'",
                ffmpegPath, screenVideoFile, audioFile, screenFile
            )
        end
        
        print("Muxing command: " .. muxCmd)
        local muxOutput = hs.execute(muxCmd .. " 2>&1")
        print("Mux output: " .. muxOutput)
        
        -- Clean up temporary files
        os.execute("rm '" .. screenVideoFile .. "' '" .. audioFile .. "' 2>&1")
        
        print("\n=== CHECKING RECORDED FILES ===")
        
        local screenCheck = hs.execute("test -f '" .. screenFile .. "' && ls -lh '" .. screenFile .. "' || echo 'NOT FOUND'")
        local webcamCheck = hs.execute("test -f '" .. webcamFile .. "' && ls -lh '" .. webcamFile .. "' || echo 'NOT FOUND'")
        
        print("Screen file: " .. screenCheck)
        print("Webcam file: " .. webcamCheck)
        
        local screenExists = not screenCheck:match("NOT FOUND")
        local webcamExists = not webcamCheck:match("NOT FOUND")
        
        print("Screen exists: " .. tostring(screenExists))
        print("Webcam exists: " .. tostring(webcamExists))
        print("==============================\n")
        
        -- Create composite video if webcam was recorded AND webcam is enabled
        if webcamSizePercent > 0 and selectedCameraDevice and selectedCameraDevice ~= "nil" and screenExists and webcamExists then
            print("Both files exist, creating composite...")
            screenRecorder.createComposite(function(success)
                -- No alerts here - just process silently
                
                -- Upload to GCS if enabled
                if autoUpload and gcsBucket ~= "" then
                    screenRecorder.uploadToGCS()
                -- else
                    -- Don't auto-open Finder anymore
                    -- os.execute("open '" .. screenRecorder.recordingFolder .. "'")
                end
                
                screenRecorder.updateMenuBar()
            end)
        elseif screenExists then
            print("Only screen recording exists (no webcam or webcam disabled), skipping composite")
            -- Copy screen.mp4 to composite.mp4 so upload can proceed
            local screenFile = screenRecorder.recordingFolder .. "/screen." .. recordFormat
            local compositeFile = screenRecorder.recordingFolder .. "/composite." .. recordFormat
            os.execute("cp '" .. screenFile .. "' '" .. compositeFile .. "'")
            
            hs.alert.show("✅ Screen recording saved")
            -- No webcam, just upload
            if autoUpload and gcsBucket ~= "" then
                screenRecorder.uploadToGCS()
            -- else
                -- Don't auto-open Finder anymore
                -- os.execute("open '" .. screenRecorder.recordingFolder .. "'")
            end
            
            screenRecorder.updateMenuBar()
        else
            print("ERROR: No files were created!")
            hs.alert.show("❌ Recording failed - check console")
            -- Only open on error for debugging
            os.execute("open '" .. screenRecorder.recordingFolder .. "'")
            screenRecorder.updateMenuBar()
        end
    end)
end

-- Create composite video with webcam overlay
function screenRecorder.createComposite(callback)
    print("\n=== CREATING COMPOSITE ===")
    
    if not screenRecorder.recordingFolder then
        print("ERROR: No recording folder set")
        callback(false)
        return
    end
    
    local screenFile = screenRecorder.recordingFolder .. "/screen." .. recordFormat
    local webcamFile = screenRecorder.recordingFolder .. "/webcam." .. recordFormat
    local compositeFile = screenRecorder.recordingFolder .. "/composite." .. recordFormat
    
    print("Screen file: " .. screenFile)
    print("Webcam file: " .. webcamFile)
    print("Composite output: " .. compositeFile)
    
    -- Check if both files exist
    local screenCheck = hs.execute("test -f '" .. screenFile .. "' && echo 'exists' || echo 'missing'")
    local webcamCheck = hs.execute("test -f '" .. webcamFile .. "' && echo 'exists' || echo 'missing'")
    
    print("Screen file check: " .. screenCheck:trim())
    print("Webcam file check: " .. webcamCheck:trim())
    
    if not screenCheck:match("exists") or not webcamCheck:match("exists") then
        print("ERROR: Missing input files for composite")
        callback(false)
        return
    end
    
    -- No alert - just process silently
    
    -- Calculate webcam position based on settings
    local positionFilter = ""
    
    if webcamPosition == "bottom-right" then
        positionFilter = "main_w-overlay_w-" .. webcamPadding .. ":main_h-overlay_h-" .. webcamPadding
    elseif webcamPosition == "bottom-left" then
        positionFilter = webcamPadding .. ":main_h-overlay_h-" .. webcamPadding
    elseif webcamPosition == "top-right" then
        positionFilter = "main_w-overlay_w-" .. webcamPadding .. ":" .. webcamPadding
    elseif webcamPosition == "top-left" then
        positionFilter = webcamPadding .. ":" .. webcamPadding
    end
    
    print("Webcam position: " .. webcamPosition)
    print("Webcam size: " .. webcamSizePercent .. "%")
    print("Webcam circle crop: " .. tostring(webcamCircleCrop))
    print("Position filter: " .. positionFilter)
    
    -- Create FFmpeg command for composite
    -- Build the filter based on circle crop setting
    local webcamFilter = ""
    
    if webcamCircleCrop then
        -- Crop to square (centered), then apply circular mask
        -- Scale to target size
        local scaleExpr = "iw*" .. (webcamSizePercent/100)
        webcamFilter = "[1:v]crop=min(iw\\,ih):min(iw\\,ih)," ..
                      "scale=" .. scaleExpr .. ":-1," ..
                      "format=yuva420p," ..
                      "geq=lum='p(X,Y)':" ..
                      "a='if(lt(pow(X-(W/2),2)+pow(Y-(H/2),2),pow(min(W,H)/2,2)),255,0)'[webcam];" ..
                      "[0:v][webcam]overlay=" .. positionFilter
    else
        -- Standard rectangular overlay
        webcamFilter = "[1:v]scale=iw*" .. (webcamSizePercent/100) .. ":-1[webcam];" ..
                      "[0:v][webcam]overlay=" .. positionFilter
    end
    
    print("Filter complex: " .. webcamFilter)
    
    -- Don't use -shortest - instead make webcam loop if it's shorter than screen
    -- This prevents webcam from freezing at the end
    local ffmpegArgs = {
        "-i", screenFile,
        "-stream_loop", "-1",  -- Loop webcam if needed
        "-i", webcamFile,
        "-filter_complex", webcamFilter,
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "23",
        "-c:a", "copy",  -- Copy audio from screen.mp4 (already synced)
        "-shortest",  -- But still end when screen (first input) ends
        "-pix_fmt", "yuv420p",
        compositeFile
    }
    
    print("Composite command: " .. ffmpegPath .. " " .. table.concat(ffmpegArgs, " "))
    
    local task = hs.task.new(ffmpegPath, 
        function(exitCode, stdOut, stdErr)
            print("\n=== COMPOSITE RESULT ===")
            print("Exit code: " .. exitCode)
            if stdErr and stdErr ~= "" then
                print("FFmpeg stderr:")
                print(stdErr)
            end
            
            -- Wait a moment for file to be fully written
            hs.timer.doAfter(1, function()
                -- Check if composite file was created
                local compositeCheck = hs.execute("test -f '" .. compositeFile .. "' && ls -lh '" .. compositeFile .. "' || echo 'NOT CREATED'")
                print("Composite file: " .. compositeCheck)
                
                local success = exitCode == 0 and not compositeCheck:match("NOT CREATED")
                print("Composite success: " .. tostring(success))
                
                -- Additional wait to ensure file is fully flushed to disk
                if success then
                    hs.timer.doAfter(1, function()
                        print("Composite ready for upload")
                        print("========================\n")
                        callback(true)
                    end)
                else
                    print("========================\n")
                    callback(false)
                end
            end)
        end,
        ffmpegArgs
    )
    
    local started = task:start()
    print("Composite task started: " .. tostring(started))
    
    if not started then
        print("ERROR: Failed to start composite task")
        callback(false)
    end
end

-- Upload to Google Cloud Storage
function screenRecorder.uploadToGCS()
    print("\n=== STARTING GCS UPLOAD ===")
    
    if not screenRecorder.recordingFolder or gcsBucket == "" then
        print("ERROR: No recording folder or bucket not configured")
        print("Recording folder: " .. tostring(screenRecorder.recordingFolder))
        print("GCS bucket: " .. tostring(gcsBucket))
        hs.alert.show("❌ No recording or bucket configured")
        return
    end
    
    local folderName = screenRecorder.recordingFolder:match("[^/]+$")
    local compositeFile = screenRecorder.recordingFolder .. "/composite." .. recordFormat
    
    print("Composite file path: " .. compositeFile)
    print("Folder name: " .. folderName)
    print("GCS bucket: " .. gcsBucket)
    print("Quick URL enabled: " .. tostring(quickUrlEnabled))
    
    -- Generate public URL
    local compositeUrl = string.format(
        "https://storage.googleapis.com/%s/%s/composite.%s",
        gcsBucket, folderName, recordFormat
    )
    
    if quickUrlEnabled then
        -- QUICK URL MODE: Placeholder already uploaded at recording start!
        print("\n🚀 QUICK URL MODE: Placeholder was uploaded when recording started")
        print("✓ URL already in clipboard from start of recording")
        
        -- Just upload the real composite to replace the placeholder
        local uploadAttempts = 0
        local maxUploadAttempts = 30  -- Wait up to 60 seconds
        
        local function uploadRealComposite()
            uploadAttempts = uploadAttempts + 1
            local compositeCheck = hs.execute("test -f '" .. compositeFile .. "' && ls -lh '" .. compositeFile .. "' || echo 'NOT FOUND'")
            
            if not compositeCheck:match("NOT FOUND") then
                print("✓ Composite ready, uploading real video to replace placeholder...")
                
                -- First, delete the old placeholder to ensure clean replacement
                local deleteCmd = string.format(
                    "%s rm 'gs://%s/%s/composite.%s' 2>&1 || echo 'No file to delete'",
                    gsutilPath, gcsBucket, folderName, recordFormat
                )
                print("Deleting placeholder: " .. deleteCmd)
                hs.execute(deleteCmd)
                
                -- Upload real composite with proper video headers and no-cache
                local compositeCmd = string.format(
                    "%s -h 'Content-Type:video/mp4' -h 'Cache-Control:no-cache, no-store, must-revalidate' cp '%s' 'gs://%s/%s/composite.%s' && %s acl ch -u AllUsers:R 'gs://%s/%s/composite.%s'",
                    gsutilPath, compositeFile, gcsBucket, folderName, recordFormat,
                    gsutilPath, gcsBucket, folderName, recordFormat
                )
                
                print("Real upload command: " .. compositeCmd)
                local uploadOutput = hs.execute(compositeCmd .. " 2>&1")
                print("Real upload output: " .. uploadOutput)
                
                hs.alert.show("✅ Video uploaded! Open URL in new tab")
                print("✅ Real composite uploaded successfully and made public")
                print("📝 Open the URL in a NEW browser tab (don't refresh old one)")
            elseif uploadAttempts < maxUploadAttempts then
                print("⚠️ Composite not ready yet (attempt " .. uploadAttempts .. "/" .. maxUploadAttempts .. "), waiting...")
                hs.timer.doAfter(2, uploadRealComposite)
            else
                print("❌ Composite upload timed out after " .. uploadAttempts .. " attempts")
                hs.alert.show("⚠️ Video upload timed out")
            end
        end
        
        -- Start checking for composite after a short delay
        hs.timer.doAfter(2, uploadRealComposite)
        
    else
        -- STANDARD MODE: Wait for composite, then upload
        print("\n📤 STANDARD MODE: Waiting for composite...")
        hs.alert.show("☁️ Uploading to GCS...")
        
        local compositeCheck = hs.execute("test -f '" .. compositeFile .. "' && ls -lh '" .. compositeFile .. "' || echo 'NOT FOUND'")
        print("Composite check result: " .. compositeCheck)
        
        if not compositeCheck:match("NOT FOUND") then
            print("✓ Composite file exists, uploading...")
            
            -- Upload using hs.execute to capture output
            local compositeCmd = string.format(
                "%s -h 'Cache-Control:public, max-age=3600' cp '%s' 'gs://%s/%s/composite.%s'",
                gsutilPath, compositeFile, gcsBucket, folderName, recordFormat
            )
            
            print("Upload command: " .. compositeCmd)
            local uploadOutput = hs.execute(compositeCmd .. " 2>&1")
            print("Upload output: " .. uploadOutput)
            
            -- Make public
            local makePublicComposite = string.format(
                "%s acl ch -u AllUsers:R 'gs://%s/%s/composite.%s'",
                gsutilPath, gcsBucket, folderName, recordFormat
            )
            
            print("Making public: " .. makePublicComposite)
            local aclOutput = hs.execute(makePublicComposite .. " 2>&1")
            print("ACL output: " .. aclOutput)
            
            hs.alert.show("✅ Video uploaded!")
            print("✅ Composite uploaded successfully")
        else
            print("⚠️ Composite not ready yet, waiting...")
            hs.timer.doAfter(2, uploadRealComposite)
        end
    end
    
    -- Don't auto-open Finder
    -- os.execute("open '" .. screenRecorder.recordingFolder .. "'")
end

-- Toggle recording
function screenRecorder.toggleRecording()
    if screenRecorder.isRecording then
        screenRecorder.stopRecording()
    else
        screenRecorder.startRecording()
    end
end

-- Update menu bar
function screenRecorder.updateMenuBar()
    local menuItems = {}
    
    -- DEBUG: Print device counts
    print("=== MENU UPDATE DEBUG ===")
    print("Available screens: " .. #availableScreens)
    print("Available cameras: " .. #availableCameras)
    print("Available audio: " .. #availableAudioDevices)
    print("Selected camera: " .. tostring(selectedCameraDevice))
    print("Selected audio: " .. tostring(selectedAudioDevice))
    print("========================")
    
    -- Recording toggle
    if screenRecorder.isRecording then
        table.insert(menuItems, {
            title = "⏹️ Stop Recording",
            fn = function() screenRecorder.stopRecording() end
        })
    else
        table.insert(menuItems, {
            title = "⏺️ Start Recording (⌘⌥S)",
            fn = function() screenRecorder.startRecording() end
        })
    end
    
    table.insert(menuItems, {title = "-"})
    
    -- Screen selection
    local screenMenu = {}
    for _, screen in ipairs(availableScreens) do
        local isSelected = screen.id == selectedScreenId
        table.insert(screenMenu, {
            title = (isSelected and "✓ " or "   ") .. screen.name,
            fn = function()
                selectedScreenId = screen.id
                currentScreenName = screen.name
                screenRecorder.updateMenuBar()
                showScreenPreview(screen.id)
            end
        })
    end
    
    table.insert(menuItems, {
        title = "📺 Screen: " .. currentScreenName,
        menu = screenMenu
    })
    
    -- Camera selection
    local cameraMenu = {}
    print("Building camera menu with " .. #availableCameras .. " cameras:")
    for i, camera in ipairs(availableCameras) do
        print("  Camera " .. i .. ": [" .. tostring(camera.index) .. "] " .. camera.name)
        local isSelected = camera.index == selectedCameraDevice
        table.insert(cameraMenu, {
            title = (isSelected and "✓ " or "   ") .. camera.name,
            fn = function()
                selectedCameraDevice = camera.index
                currentCameraName = camera.name
                print("Selected camera: [" .. tostring(camera.index) .. "] " .. camera.name)
                saveConfig()
                screenRecorder.updateMenuBar()
            end
        })
    end
    
    table.insert(menuItems, {
        title = "📷 Camera: " .. currentCameraName,
        menu = cameraMenu
    })
    
    -- Audio device selection
    local audioMenu = {}
    print("Building audio menu with " .. #availableAudioDevices .. " devices:")
    for i, audio in ipairs(availableAudioDevices) do
        print("  Audio " .. i .. ": [" .. tostring(audio.index) .. "] " .. audio.name)
        local isSelected = (":" .. audio.index) == selectedAudioDevice
        table.insert(audioMenu, {
            title = (isSelected and "✓ " or "   ") .. audio.name,
            fn = function()
                selectedAudioDevice = ":" .. audio.index
                currentAudioName = audio.name
                print("Selected audio: [" .. tostring(audio.index) .. "] " .. audio.name)
                saveConfig()
                screenRecorder.updateMenuBar()
            end
        })
    end
    
    table.insert(menuItems, {
        title = "🎤 Audio: " .. currentAudioName,
        menu = audioMenu
    })
    
    table.insert(menuItems, {title = "-"})
    
    -- Webcam position
    local positionMenu = {
        {
            title = (webcamPosition == "bottom-right" and "✓ " or "   ") .. "Bottom Right",
            fn = function()
                webcamPosition = "bottom-right"
                saveConfig()
                screenRecorder.updateMenuBar()
            end
        },
        {
            title = (webcamPosition == "bottom-left" and "✓ " or "   ") .. "Bottom Left",
            fn = function()
                webcamPosition = "bottom-left"
                saveConfig()
                screenRecorder.updateMenuBar()
            end
        },
        {
            title = (webcamPosition == "top-right" and "✓ " or "   ") .. "Top Right",
            fn = function()
                webcamPosition = "top-right"
                saveConfig()
                screenRecorder.updateMenuBar()
            end
        },
        {
            title = (webcamPosition == "top-left" and "✓ " or "   ") .. "Top Left",
            fn = function()
                webcamPosition = "top-left"
                saveConfig()
                screenRecorder.updateMenuBar()
            end
        }
    }
    
    table.insert(menuItems, {
        title = "📐 Webcam Position: " .. webcamPosition,
        menu = positionMenu
    })
    
    -- Webcam size
    local sizeMenu = {
        {
            title = (webcamSizePercent == 0 and "✓ " or "   ") .. "Off (No Webcam)",
            fn = function()
                webcamSizePercent = 0
                saveConfig()
                screenRecorder.updateMenuBar()
                showWebcamPreview(0)
            end
        },
        {
            title = (webcamSizePercent == 5 and "✓ " or "   ") .. "Tiny (5%)",
            fn = function()
                webcamSizePercent = 5
                saveConfig()
                screenRecorder.updateMenuBar()
                showWebcamPreview(5)
            end
        },
        {
            title = (webcamSizePercent == 10 and "✓ " or "   ") .. "Mini (10%)",
            fn = function()
                webcamSizePercent = 10
                saveConfig()
                screenRecorder.updateMenuBar()
                showWebcamPreview(10)
            end
        },
        {
            title = (webcamSizePercent == 15 and "✓ " or "   ") .. "Small (15%)",
            fn = function()
                webcamSizePercent = 15
                saveConfig()
                screenRecorder.updateMenuBar()
                showWebcamPreview(15)
            end
        },
        {
            title = (webcamSizePercent == 20 and "✓ " or "   ") .. "Medium (20%)",
            fn = function()
                webcamSizePercent = 20
                saveConfig()
                screenRecorder.updateMenuBar()
                showWebcamPreview(20)
            end
        },
        {
            title = (webcamSizePercent == 25 and "✓ " or "   ") .. "Large (25%)",
            fn = function()
                webcamSizePercent = 25
                saveConfig()
                screenRecorder.updateMenuBar()
                showWebcamPreview(25)
            end
        },
        {
            title = (webcamSizePercent == 30 and "✓ " or "   ") .. "Extra Large (30%)",
            fn = function()
                webcamSizePercent = 30
                saveConfig()
                screenRecorder.updateMenuBar()
                showWebcamPreview(30)
            end
        },
        {
            title = (webcamSizePercent == 35 and "✓ " or "   ") .. "Huge (35%)",
            fn = function()
                webcamSizePercent = 35
                saveConfig()
                screenRecorder.updateMenuBar()
                showWebcamPreview(35)
            end
        }
    }
    
    table.insert(menuItems, {
        title = "📏 Webcam Size: " .. (webcamSizePercent == 0 and "Off" or webcamSizePercent .. "%"),
        menu = sizeMenu
    })
    
    -- Webcam circle crop toggle
    table.insert(menuItems, {
        title = (webcamCircleCrop and "✓" or "  ") .. " ⭕ Crop Webcam to Circle",
        fn = function()
            webcamCircleCrop = not webcamCircleCrop
            saveConfig()
            screenRecorder.updateMenuBar()
        end
    })
    
    table.insert(menuItems, {title = "-"})
    
    -- Audio gain control
    local gainMenu = {
        {
            title = (audioGain == 0.3 and "✓ " or "   ") .. "30% (Very Low)",
            fn = function()
                audioGain = 0.3
                saveConfig()
                screenRecorder.updateMenuBar()
            end
        },
        {
            title = (audioGain == 0.5 and "✓ " or "   ") .. "50% (Low - Recommended)",
            fn = function()
                audioGain = 0.5
                saveConfig()
                screenRecorder.updateMenuBar()
            end
        },
        {
            title = (audioGain == 0.7 and "✓ " or "   ") .. "70% (Medium)",
            fn = function()
                audioGain = 0.7
                saveConfig()
                screenRecorder.updateMenuBar()
            end
        },
        {
            title = (audioGain == 1.0 and "✓ " or "   ") .. "100% (Normal)",
            fn = function()
                audioGain = 1.0
                saveConfig()
                screenRecorder.updateMenuBar()
            end
        },
        {
            title = (audioGain == 1.5 and "✓ " or "   ") .. "150% (High)",
            fn = function()
                audioGain = 1.5
                saveConfig()
                screenRecorder.updateMenuBar()
            end
        }
    }
    
    table.insert(menuItems, {
        title = "🎙️ Audio Gain: " .. (audioGain * 100) .. "%",
        menu = gainMenu
    })
    
    table.insert(menuItems, {title = "-"})
    
    -- Auto-upload toggle
    table.insert(menuItems, {
        title = (autoUpload and "✓" or "  ") .. " Auto-upload to GCS",
        fn = function()
            autoUpload = not autoUpload
            saveConfig()
            screenRecorder.updateMenuBar()
        end
    })
    
    -- Quick URL toggle (beta feature)
    table.insert(menuItems, {
        title = (quickUrlEnabled and "✓" or "  ") .. " ⚡ Get URL Quicker (Beta)",
        fn = function()
            quickUrlEnabled = not quickUrlEnabled
            saveConfig()
            screenRecorder.updateMenuBar()
        end
    })
    
    -- GCS bucket configuration
    table.insert(menuItems, {
        title = "☁️ GCS Bucket: " .. (gcsBucket ~= "" and gcsBucket or "Not configured"),
        fn = function()
            local button, text = hs.dialog.textPrompt(
                "Google Cloud Storage Bucket",
                "Enter your GCS bucket name:",
                gcsBucket,
                "OK",
                "Cancel"
            )
            if button == "OK" and text then
                gcsBucket = text:trim()
                
                -- Auto-enable upload when bucket is configured
                if gcsBucket ~= "" then
                    autoUpload = true
                    hs.alert.show("✓ Auto-upload enabled")
                end
                
                saveConfig()
                screenRecorder.updateMenuBar()
            end
        end
    })
    
    table.insert(menuItems, {title = "-"})
    
    -- Open recordings folder
    table.insert(menuItems, {
        title = "📁 Open Recordings Folder",
        fn = function()
            os.execute("open '" .. recordingDirectory .. "'")
        end
    })
    
    -- Refresh devices
    table.insert(menuItems, {
        title = "🔄 Refresh Devices",
        fn = function()
            screenRecorder.enumerateScreens()
            screenRecorder.enumerateCameras()
            screenRecorder.updateMenuBar()
            hs.alert.show("Devices refreshed")
        end
    })
    
    menuBar:setMenu(menuItems)
end

-- Initialize
function screenRecorder.init()
    -- Ensure directory exists
    screenRecorder.ensureDirectory()
    
    -- Load saved configuration
    loadConfig()
    
    -- Enumerate devices (cameras must be called first as it populates audio too)
    screenRecorder.enumerateScreens()
    screenRecorder.enumerateCameras()  -- This populates both camera and audio lists
    screenRecorder.enumerateAudioDevices()  -- This sets defaults if needed
    
    -- Create menu bar
    menuBar = hs.menubar.new()
    menuBar:setTitle("📹")
    menuBar:setTooltip("Screen Recorder")
    
    -- Set up keyboard shortcut (Cmd+Option+S)
    hs.hotkey.bind({"cmd", "alt"}, "S", function()
        screenRecorder.toggleRecording()
    end)
    
    screenRecorder.updateMenuBar()
    
    print("Screen Recorder loaded successfully")
    print("Press Cmd+Option+S to start/stop recording")
    print("Cameras: " .. #availableCameras .. ", Audio devices: " .. #availableAudioDevices)
end

-- Start the recorder
screenRecorder.init()

return screenRecorder
