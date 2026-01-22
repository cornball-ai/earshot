// Earshot Microphone Recorder
// Uses MediaRecorder API to capture audio from browser

(function() {
  let mediaRecorder = null;
  let audioChunks = [];
  let isRecording = false;
  let streamMode = false;
  let chunkIndex = 0;
  let currentStream = null;
  let webmHeader = null;  // Cached header from first chunk

  // Initialize when Shiny is ready
  $(document).on('shiny:connected', function() {
    const recordBtn = document.getElementById('record_btn');
    if (!recordBtn) return;

    recordBtn.addEventListener('click', toggleRecording);

    // Listen for stream mode changes
    Shiny.addCustomMessageHandler('set_stream_mode', function(enabled) {
      streamMode = enabled;
    });
  });

  async function toggleRecording() {
    if (isRecording) {
      stopRecording();
    } else {
      await startRecording();
    }
  }

  async function startRecording() {
    // Check for secure context (HTTPS or localhost)
    if (!window.isSecureContext) {
      Shiny.setInputValue('recording_error',
        'Microphone requires HTTPS. Access via localhost or enable HTTPS.');
      return;
    }

    // Check for mediaDevices API
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      Shiny.setInputValue('recording_error',
        'Microphone not supported in this browser. Try Chrome or Firefox.');
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      currentStream = stream;

      // Use webm for broad compatibility, fallback to default
      const mimeType = MediaRecorder.isTypeSupported('audio/webm')
        ? 'audio/webm'
        : '';

      mediaRecorder = new MediaRecorder(stream, mimeType ? { mimeType } : {});
      audioChunks = [];
      chunkIndex = 0;
      webmHeader = null;

      // Check current stream mode state from checkbox
      const streamCheckbox = document.getElementById('stream_mode');
      streamMode = streamCheckbox ? streamCheckbox.checked : false;

      mediaRecorder.ondataavailable = async (event) => {
        if (event.data.size > 0) {
          audioChunks.push(event.data);

          // In stream mode, send each chunk with header prepended
          if (streamMode && isRecording) {
            let blobToSend;

            if (chunkIndex === 0) {
              // First chunk has full header - extract and cache it
              const arrayBuffer = await event.data.arrayBuffer();
              const headerEnd = findClusterOffset(new Uint8Array(arrayBuffer));
              if (headerEnd > 0) {
                webmHeader = arrayBuffer.slice(0, headerEnd);
              }
              blobToSend = event.data;
            } else if (webmHeader) {
              // Prepend cached header to subsequent chunks
              blobToSend = new Blob([webmHeader, event.data], { type: 'audio/webm' });
            } else {
              // Fallback: send accumulated if header extraction failed
              blobToSend = new Blob(audioChunks, { type: 'audio/webm' });
            }

            sendChunkToShiny(blobToSend, chunkIndex);
            chunkIndex++;
          }
        }
      };

      mediaRecorder.onstop = () => {
        // Stop all tracks to release microphone
        stream.getTracks().forEach(track => track.stop());
        currentStream = null;

        // Convert to blob and send to Shiny
        const audioBlob = new Blob(audioChunks, { type: 'audio/webm' });
        sendAudioToShiny(audioBlob);

        // Signal streaming complete if in stream mode
        if (streamMode) {
          Shiny.setInputValue('streaming_complete', {
            total_chunks: chunkIndex,
            timestamp: Date.now()
          });
        }
      };

      // In stream mode, use timeslice to get chunks every 3 seconds
      // Otherwise, collect all audio until stop
      if (streamMode) {
        mediaRecorder.start(3000); // 3 second chunks
      } else {
        mediaRecorder.start();
      }

      isRecording = true;
      updateUI(true);

      Shiny.setInputValue('recording_status', 'recording');

    } catch (err) {
      console.error('Microphone access error:', err);
      Shiny.setInputValue('recording_error', err.message);
    }
  }

  // Find offset of first Cluster element in WebM data
  // Cluster element ID: 0x1F 0x43 0xB6 0x75
  function findClusterOffset(data) {
    const clusterId = [0x1F, 0x43, 0xB6, 0x75];
    for (let i = 0; i < data.length - 4; i++) {
      if (data[i] === clusterId[0] &&
          data[i+1] === clusterId[1] &&
          data[i+2] === clusterId[2] &&
          data[i+3] === clusterId[3]) {
        return i;
      }
    }
    return -1;
  }

  function sendChunkToShiny(blob, index) {
    const reader = new FileReader();
    reader.onloadend = () => {
      const base64data = reader.result.split(',')[1];
      // priority: "event" forces Shiny to trigger observer for each chunk
      Shiny.setInputValue('streaming_chunk', {
        data: base64data,
        type: blob.type,
        size: blob.size,
        index: index,
        timestamp: Date.now()
      }, {priority: "event"});
    };
    reader.readAsDataURL(blob);
  }

  function stopRecording() {
    if (mediaRecorder && mediaRecorder.state !== 'inactive') {
      mediaRecorder.stop();
      isRecording = false;
      updateUI(false);
      Shiny.setInputValue('recording_status', 'stopped');
    }
  }

  function updateUI(recording) {
    const recordBtn = document.getElementById('record_btn');
    if (!recordBtn) return;

    if (recording) {
      recordBtn.textContent = 'Stop';
      recordBtn.classList.add('recording');
    } else {
      recordBtn.textContent = 'Record';
      recordBtn.classList.remove('recording');
    }
  }

  function sendAudioToShiny(blob) {
    const reader = new FileReader();
    reader.onloadend = () => {
      // Send base64 data to Shiny (strip data URL prefix)
      const base64data = reader.result.split(',')[1];
      Shiny.setInputValue('recorded_audio', {
        data: base64data,
        type: blob.type,
        size: blob.size,
        timestamp: Date.now()
      });
    };
    reader.readAsDataURL(blob);
  }
})();
