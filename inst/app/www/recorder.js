// Earshot Microphone Recorder
// Uses MediaRecorder API to capture audio from browser

(function() {
  let mediaRecorder = null;
  let audioChunks = [];
  let isRecording = false;

  // Initialize when Shiny is ready
  $(document).on('shiny:connected', function() {
    const recordBtn = document.getElementById('record_btn');
    if (!recordBtn) return;

    recordBtn.addEventListener('click', toggleRecording);
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

      // Use webm for broad compatibility, fallback to default
      const mimeType = MediaRecorder.isTypeSupported('audio/webm')
        ? 'audio/webm'
        : '';

      mediaRecorder = new MediaRecorder(stream, mimeType ? { mimeType } : {});
      audioChunks = [];

      mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          audioChunks.push(event.data);
        }
      };

      mediaRecorder.onstop = () => {
        // Stop all tracks to release microphone
        stream.getTracks().forEach(track => track.stop());

        // Convert to blob and send to Shiny
        const audioBlob = new Blob(audioChunks, { type: 'audio/webm' });
        sendAudioToShiny(audioBlob);
      };

      mediaRecorder.start();
      isRecording = true;
      updateUI(true);

      Shiny.setInputValue('recording_status', 'recording');

    } catch (err) {
      console.error('Microphone access error:', err);
      Shiny.setInputValue('recording_error', err.message);
    }
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
