# MPU6050/TL... Bubble Level for Tasmota/Berry

# Based on proven Toit implementation - uses vector projection for calibration
# Auto-saves calibration to flash using persist module

# during development we can also load the driver with
# can be used with load("level"). This allows for multiple reloads

if global.level != nil
  try
    global.level.cleanup() # remove timers triggers generated global structures etc
  except .. as e, m
    print('Error', e, m)
  end
  global.level = nil # remove the global object
  tasmota.gc() # clean the GC bebore proceed # y
end

var level
do
  import strict
  import math
  import string
  import persist

  var MSG = 'LEVEL: '
  var MPU_ADDR = 0x68

  class LEVEL
    var w              # Wire/I2C object (passed in, not scanned)
    var addr           # I2C address
    
    # Calibration vector - the normalized gravity vector when device is level
    var cal_x
    var cal_y
    var cal_z
    var calibrated
    # Tilt monitor
    var tilt_callback
    var tilt_max_angle # in degrees
    var tilt_interval
    static PERSIST_KEY = 'calibration'

    def init(wire, addr)
      # wire: tasmota wire_scan result (already validated)
      # addr: I2C address
      
      self.cal_x = 0.0
      self.cal_y = 0.0
      self.cal_z = 1.0
      self.calibrated = false
      self.w = wire
      if addr == nil addr = MPU_ADDR end
      self.addr = addr
      #self.monitor_activated = false
      self._configure()
      
      # Try to load saved calibration
      self._load_calibration()
    end

    # Configure MPU6050: wake up, set range, enable low-pass filter
    def _configure()
      # Wake up (clear sleep bit)
      self.w.write_bytes(self.addr, 0x6B, bytes().add(0x00, 1))
      # Set accelerometer range to ±2g
      self.w.write_bytes(self.addr, 0x1C, bytes().add(0x00, 1))
      # Set DLPF to ~44Hz to reduce noise
      self.w.write_bytes(self.addr, 0x1A, bytes().add(0x03, 1))
    end

    # Internal: load calibration from flash
    def _load_calibration()
      var saved = persist.find(LEVEL.PERSIST_KEY)
      if saved == nil
        print(MSG + 'No saved calibration found. Run: level.calibrate()')
        return
      end
      
      # Let set_calibration handle all validation
      if self.set_calibration(saved, true)  # true = from flash
        print(MSG + 'Loaded calibration from flash')
      else
        # Invalid data in flash, remove it
        persist.remove(LEVEL.PERSIST_KEY)
        print('The flash data are ivalid. Run level.calibrate() again')
      end
    end

    # Internal: save calibration to flash
    def _save_calibration()
      if !self.calibrated
        return false
      end
      
      var cal = [self.cal_x, self.cal_y, self.cal_z]
      persist.setmember(LEVEL.PERSIST_KEY, cal)
      persist.save()
      print(MSG + 'Calibration saved to flash')
    end

    # Read accelerometer and return [ax, ay, az] in g units
    def read_accel()
      var d = self.w.read_bytes(self.addr, 0x3B, 6)
      if size(d) != 6
        return nil
      end
      
      def to_i16(h, l)
        var v = (h << 8) | l
        if v > 32767 v -= 65536 end
        return v
      end
      
      var scale = 16384.0
      return [
        to_i16(d[0], d[1]) / scale,
        to_i16(d[2], d[3]) / scale,
        to_i16(d[4], d[5]) / scale
      ]
    end

    # Get total tilt angle in radians
    def tilt_rad()
      if !self.calibrated
        print(MSG + 'Warning: Not calibrated. Run: level.calibrate()')
        return nil
      end
      
      var a = self.read_accel()
      if a == nil return nil end
      
      var ax = a[0]
      var ay = a[1]
      var az = a[2]
      
      # Project onto calibrated Z axis
      var device_Z = ax * self.cal_x + ay * self.cal_y + az * self.cal_z
      
      # z_angle: total tilt from vertical (direct from gravity projection)
      var accel_mag = math.sqrt(ax*ax + ay*ay + az*az)
      var z_angle = math.acos(device_Z / accel_mag)
      return z_angle
    end

    # Calibrate: measure gravity vector when device is in "level" position
    # Saves to flash automatically
    def calibrate(samples)
      if samples == nil samples = 20 end
      
      print(MSG + 'Calibrating... keep steady (' .. samples .. ' samples)')
      
      var sum_x = 0.0
      var sum_y = 0.0
      var sum_z = 0.0
      
      var i = 0
      while i < samples
        var a = self.read_accel()
        if a != nil
          sum_x += a[0]
          sum_y += a[1]
          sum_z += a[2]
          i += 1
        end
      end
      
      # Normalize to unit vector
      var len = math.sqrt(sum_x*sum_x + sum_y*sum_y + sum_z*sum_z)
      if len < 0.1
        print(MSG + 'Error: Invalid calibration')
        return nil
      end
      
      # Use set_calibration to normalize and set (avoids duplicate code)
      var cal_vector = [sum_x / len, sum_y / len, sum_z / len]
      self.set_calibration(cal_vector)
      
      # Save to flash
      self._save_calibration()
    end

    # Set calibration vector (e.g., manually loaded or from flash)
    # vector: [x, y, z] - will be normalized if not already unit length
    # from_flash: if true, suppress print (used by _load_calibration)
    def set_calibration(vector, from_flash)
      if from_flash == nil from_flash = false end
      
      # Validate: must be list of 3 numbers
      if type(vector) != 'instance' || classname(vector) != 'list' || size(vector) != 3
        if !from_flash
          print(MSG + 'Error: Calibration vector must be a list of 3 numbers')
        end
        return false
      end
      
      var x = vector[0]
      var y = vector[1]
      var z = vector[2]
      
      # Normalize to unit vector
      var len = math.sqrt(x*x + y*y + z*z)
      if len < 0.1
        if !from_flash
          print(MSG + 'Error: Invalid calibration vector (too small)')
        end
        return false
      end
      
      self.cal_x = x / len
      self.cal_y = y / len
      self.cal_z = z / len
      self.calibrated = true
      
      if !from_flash
        print(MSG + 'Calibration loaded: [' .. 
              string.format('%.4f', self.cal_x) .. ', ' ..
              string.format('%.4f', self.cal_y) .. ', ' ..
              string.format('%.4f', self.cal_z) .. ']')
      end
      
      return true
    end

    # Helper: radians to degrees
    def _deg(rad)
      if rad == nil return nil end
      return rad * 180.0 / math.pi
    end

    # Get total tilt angle in degrees (most common use)
    def tilt()
      return self._deg(self.tilt_rad())
    end

    def tilt_monitor(callback, interval)
      #self.stop_tilt_monitor()
      tasmota.remove_timer(self)
      if interval == nil interval = 100 end
      if type(interval) != 'int' || interval<=0
        print('Wrong value for interval, must be ms')
        return
      end
      #if callback == nil
      #  callback = /t-> print("tilt =",t)
      #end
      if type(callback)!='function'
        print('Callback must be a function')
        return
      end
      self.tilt_callback = callback
      print("Starting tilt monitor")
      self._tilt()
    end

    def stop_tilt_monitor()
      if self.tilt_callback
        self.tilt_callback = nil
        print('Tilt monitor is stopped')
      end
      tasmota.remove_timer(self)
    end

    def _tilt()
      var t = self.tilt()
      if t>10
        print("Tilt detected") # monitor is stopped, it needs to reenable
        var cb = self.tilt_callback
        self.tilt_callback = nil
        cb(t)
      else
        tasmota.set_timer(100, /->self._tilt(), self)
      end
    end

    def deinit()
      # We need the message to know if BerryVM removes the old instance(on reload)
      print(self, 'deinit')
    end
  end

  # Scan for MPU6050 before creating instance
  # var addr = MPU_ADDR
  var wire = tasmota.wire_scan(MPU_ADDR)
  
  if wire == nil # NO devoce at all
    print(MSG + 'MPU6050 not found at 0x' .. string.hex(MPU_ADDR))
    print(MSG + 'Driver not loaded')
  elif wire.read(0x68,0x75,1)!=0x68 # WHO_AM_I register
    print(MSG .. 'The device at ' .. string.hex(MPU_ADDR) .. 'is not a MPU6050')
    print(MSG + 'Driver not loaded')
  else # MPU6050 is wired
    print(MSG + 'MPU6050 found at 0x' .. string.hex(MPU_ADDR))
    # Create global "level" instance
    #global.
    level = LEVEL(wire, MPU_ADDR)
    return level
  end
end
