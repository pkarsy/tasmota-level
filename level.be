# Bubble Level for Tasmota/Berry - Supports QMI8658, MPU6050, LSM6DS3, ADXL345, BMI160

# during development we can also load the driver with
# load("level"). This allows for multiple reloads

if global.level != nil
  try
    global.level.cleanup()  # Remove timers, rules, etc
  except .. as e, m
    print('Cleanup method is not present:', e, m)
  end
  global.level = nil # remove the global object
  tasmota.gc() # clean the GC before proceed
end


var level = nil

do
  import strict
  import math
  import string
  import persist

  var MSG = 'LEVEL: '

  # Configure MPU6050: wake up, set range, enable low-pass filter
  def mpu6050_init()
    var MPU6050_ADDR = 0x68
    var addr = MPU6050_ADDR
    var w = tasmota.wire_scan(MPU6050_ADDR)
    if w == nil # NO device at all
      print(MSG + 'MPU6050 not found at 0x' .. string.hex(MPU6050_ADDR))
      return nil
    elif w.read(addr, 0x75, 1) != 0x68 # WHO_AM_I register
      print(MSG + 'The device at 0x' .. string.hex(MPU6050_ADDR) .. ' is not a MPU6050')
      return nil
    else # MPU6050 is wired
      print(MSG + 'MPU6050 found at 0x' .. string.hex(MPU6050_ADDR))
      # Wake up (clear sleep bit)
      w.write_bytes(addr, 0x6B, bytes().add(0x00, 1))
      # Set accelerometer range to ±2g
      w.write_bytes(addr, 0x1C, bytes().add(0x00, 1))
      # Set DLPF to ~44Hz to reduce noise
      w.write_bytes(addr, 0x1A, bytes().add(0x03, 1))
      return [MPU6050_ADDR, w]
    end
  end

  # Read accelerometer and return [ax, ay, az] in g units
  # The addr is always 0x68 but the function must be compatible with all x_read_accel functions
  def mpu6050_read_accel(addr, w)
    var d = w.read_bytes(addr, 0x3B, 6)
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

  # Initialize and configure the QMI8658
  def qmi8658_init()
    # Define I2C Address - Try 0x6A first, then 0x6B if it doesn't work.
    var QMI8658_ADDR1 = 0x6A
    var QMI8658_ADDR2 = 0x6B
    var QMI8658_REG_WHO_AM_I = 0x00   # Should return 0x05
    var QMI8658_REG_RESET = 0x60
    var QMI8658_REG_CTRL1 = 0x02
    var QMI8658_REG_CTRL7 = 0x08
    var QMI8658_REG_CTRL2 = 0x03
    var QMI8658_REG_CTRL3 = 0x04
    var w = nil
    var addr = 0
    w = tasmota.wire_scan(QMI8658_ADDR1)
    if w == nil
      w = tasmota.wire_scan(QMI8658_ADDR2)
      if w == nil
        print(MSG + 'QMI8658 not found')
        return nil
      else
        addr = QMI8658_ADDR2
      end
    else
      addr = QMI8658_ADDR1
    end
    # Verify the sensor is present
    var id = w.read_bytes(addr, QMI8658_REG_WHO_AM_I, 1)
    if id == nil || id.size() == 0
      print(MSG + 'QMI8658: Failed to read WHO_AM_I')
      return nil
    end
    if id[0] != 0x05
      print(MSG + 'QMI8658: Invalid WHO_AM_I value: ' + str(id[0]))
      return nil
    end
    print(MSG + 'QMI8658 found at 0x' .. string.hex(addr))
    # --- 2. Reset the sensor (recommended) ---
    w.write_bytes(addr, QMI8658_REG_RESET, bytes().add(0xB0, 1))
    tasmota.delay(50)  # Wait for reset to complete (blocking, happens once at init)
    # --- 3. Configure the sensor ---
    # CTRL1: Set address auto-increment (0x40) and enable accelerometer low-pass filter
    w.write_bytes(addr, QMI8658_REG_CTRL1, bytes().add(0x40, 1))
    # CTRL7: Enable Accelerometer and Gyroscope (0x03)
    w.write_bytes(addr, QMI8658_REG_CTRL7, bytes().add(0x03, 1))
    # CTRL2: Configure Accelerometer
    # 0x95 = ODR 250Hz, Full Scale ±4g, High Performance mode
    # For ±2g scale (matching your MPU6050 config), we need 0x85
    w.write_bytes(addr, QMI8658_REG_CTRL2, bytes().add(0x85, 1))
    # CTRL3: Configure Gyroscope (optional, but included)
    # self.w.write_bytes(addr, QMI8658_REG_CTRL3, bytes().add(0xD5, 1)) # 512dps, 250Hz
    tasmota.delay(10)
    return [addr, w]
  end

  # Read accelerometer and return [ax, ay, az] in g units
  def qmi8658_read_accel(addr, w)
    var QMI8658_REG_AX_L = 0x35        # Accelerometer X-axis low byte
    # Read 6 bytes starting from the AX_L register (0x35)
    var d = w.read_bytes(addr, QMI8658_REG_AX_L, 6)
    if size(d) != 6
      print("QMI8658: Failed to read accelerometer data")
      return nil
    end
    # Helper function to convert two bytes to a signed 16-bit integer (Little Endian for QMI8658!)
    def to_i16(l, h)
      var v = (h << 8) | l
      if v > 32767
        v -= 65536
      end
      return v
    end
    # Scale factor for ±2g (16-bit output)
    # Sensitivity is 16384 LSB/g. To get g, divide raw value by 16384.0
    var scale = 16384.0
    # Note: QMI8658 stores data in Little Endian format (low byte first).
    # This is different from MPU6050 (Big Endian).
    return [
      to_i16(d[0], d[1]) / scale,
      to_i16(d[2], d[3]) / scale,
      to_i16(d[4], d[5]) / scale
    ]
  end


  # Initialize LSM6DS3
  # Returns: [addr, wire] or nil on failure
  def lsm6ds3_init()
    # LSM6DS3 Register Map
    var LSM6DS3_ADDR1 = 0x6A  # Default SA0 low
    var LSM6DS3_ADDR2 = 0x6B  # SA0 high
    var LSM6DS3_WHO_AM_I = 0x0F    # Should return 0x69
    # Control registers
    var LSM6DS3_CTRL1_XL = 0x10    # Accelerometer control
    var LSM6DS3_CTRL2_G = 0x11     # Gyroscope control
    var LSM6DS3_CTRL3_C = 0x12     # Control register 3
    var addr = 0
    # Try both addresses
    var w = tasmota.wire_scan(LSM6DS3_ADDR1)
    if w == nil
      w = tasmota.wire_scan(LSM6DS3_ADDR2)
      if w == nil
        print(MSG + 'LSM6DS3 not found')
        return nil
      else
        addr = LSM6DS3_ADDR2
      end
    else
      addr = LSM6DS3_ADDR1
    end
    # Check WHO_AM_I
    var id = w.read_bytes(addr, LSM6DS3_WHO_AM_I, 1)
    if id == nil || id.size() == 0
      print(MSG + 'LSM6DS3: Failed to read WHO_AM_I')
      return nil
    end
    if id[0] != 0x69 && id[0] != 0x6A  # 0x69 for LSM6DS3, 0x6A for LSM6DS3TR-C
      print(MSG + 'LSM6DS3: Invalid WHO_AM_I: 0x' + string.hex(id[0]))
      return nil
    end
    print(MSG + 'LSM6DS3 found at 0x' .. string.hex(addr))
    # Software reset
    w.write_bytes(addr, LSM6DS3_CTRL3_C, bytes().add(0x01, 1))  # SW_RESET
    tasmota.delay(10)
    # Configure accelerometer:
    # CTRL1_XL: ODR=104Hz, FS=±2g, BW=50Hz
    # 0x40 = 0100 0000 = 104Hz, 2g
    # 0x44 = 0100 0100 = 104Hz, 4g
    # 0x48 = 0100 1000 = 104Hz, 8g
    # 0x4C = 0100 1100 = 104Hz, 16g
    w.write_bytes(addr, LSM6DS3_CTRL1_XL, bytes().add(0x40, 1))  # 104Hz, ±2g
    # Enable Block Data Update (BDU) for consistent reads
    var ctrl3 = w.read_bytes(addr, LSM6DS3_CTRL3_C, 1)
    if ctrl3 != nil
      w.write_bytes(addr, LSM6DS3_CTRL3_C, bytes().add(ctrl3[0] | 0x40, 1))
    end
    tasmota.delay(10)
    print(MSG + 'LSM6DS3 configured (104Hz, ±2g)')
    return [addr, w]
  end

  # Read accelerometer from LSM6DS3
  # Returns: [ax, ay, az] in g units or nil on failure
  def lsm6ds3_read_accel(addr, w)
    # Output registers
    var LSM6DS3_OUTX_L_XL = 0x28   # Accelerometer X low byte
    #var LSM6DS3_OUTX_L_G = 0x22    # Gyroscope X low byte
    # Read 6 bytes starting from OUTX_L_XL (0x28)
    # Auto-increment is enabled by default
    var d = w.read_bytes(addr, LSM6DS3_OUTX_L_XL, 6)
    if d == nil || size(d) != 6
      print("LSM6DS3: Failed to read accelerometer")
      return nil
    end
    # Convert to signed 16-bit (little endian)
    def to_i16(l, h)
      var v = (h << 8) | l
      if v > 32767 v -= 65536 end
      return v
    end
    # Scale for ±2g: 16384 LSB/g (same as MPU6050)
    var scale = 16384.0
    return [
      to_i16(d[0], d[1]) / scale,
      to_i16(d[2], d[3]) / scale,
      to_i16(d[4], d[5]) / scale
    ]
  end

  ###############################################################################
  # BMI160 support
  ###############################################################################

  # Initialize BMI160
  # Returns: [addr, wire] or nil on failure
  def bmi160_init()
    # BMI160 I2C addresses: 0x68 (SDO low) or 0x69 (SDO high)
    var BMI160_ADDR1 = 0x68
    var BMI160_ADDR2 = 0x69
    var BMI160_CHIP_ID = 0x00          # Should return 0xD1
    var BMI160_PMU_STATUS = 0x03       # Power mode status
    var BMI160_CMD = 0x7E              # Command register
    var BMI160_ACC_CONF = 0x40         # Accelerometer config
    var BMI160_ACC_RANGE = 0x41        # Accelerometer range

    var addr = 0
    var w = tasmota.wire_scan(BMI160_ADDR1)
    if w == nil
      w = tasmota.wire_scan(BMI160_ADDR2)
      if w == nil
        print(MSG + 'BMI160 not found')
        return nil
      else
        addr = BMI160_ADDR2
      end
    else
      addr = BMI160_ADDR1
    end

    # Check chip ID
    var id = w.read_bytes(addr, BMI160_CHIP_ID, 1)
    if id == nil || id.size() == 0
      print(MSG + 'BMI160: Failed to read CHIP_ID')
      return nil
    end
    if id[0] != 0xD1
      print("BMI160: Invalid CHIP_ID: 0x" + string.hex(id[0]))
      return nil
    end
    print(MSG + 'BMI160 found at 0x' + string.hex(addr))

    # Set accelerometer to normal mode (0x11 command)
    w.write_bytes(addr, BMI160_CMD, bytes().add(0x11, 1))
    tasmota.delay(5)

    # Set accelerometer range to ±2g (0x03)
    w.write_bytes(addr, BMI160_ACC_RANGE, bytes().add(0x03, 1))
    tasmota.delay(1)

    # Set output data rate to 100Hz
    w.write_bytes(addr, BMI160_ACC_CONF, bytes().add(0x28, 1))
    tasmota.delay(1)

    print(MSG + 'BMI160 configured (100Hz, ±2g)')
    return [addr, w]
  end

  # Read accelerometer from BMI160
  # Returns: [ax, ay, az] in g units or nil on failure
  def bmi160_read_accel(addr, w)
    var BMI160_ACC_DATA_X_LSB = 0x12   # Accelerometer X low byte
    # Read 6 bytes (X low, X high, Y low, Y high, Z low, Z high)
    var d = w.read_bytes(addr, BMI160_ACC_DATA_X_LSB, 6)
    if d == nil || size(d) != 6
      print(MSG + 'BMI160: Failed to read accelerometer data')
      return nil
    end

    # Helper: convert little-endian (low byte first) to signed int16
    def to_i16(l, h)
      var v = (h << 8) | l
      if v > 32767
        v -= 65536
      end
      return v
    end

    # Scale factor: ±2g range has 16384 LSB/g (same as MPU6050)
    var scale = 16384.0

    return [
      to_i16(d[0], d[1]) / scale,
      to_i16(d[2], d[3]) / scale,
      to_i16(d[4], d[5]) / scale
    ]
  end

  ###############################################################################
  # ADXL345 support
  ###############################################################################

  # Initialize ADXL345
  # Returns: [addr, wire] or nil on failure
  def adxl345_init()
    # ADXL345 I2C addresses: 0x53 (SDO low) or 0x1D (SDO high)
    var ADXL345_ADDR1 = 0x53
    var ADXL345_ADDR2 = 0x1D
    var ADXL345_DEVID = 0x00          # Should return 0xE5
    var ADXL345_POWER_CTL = 0x2D
    var ADXL345_DATA_FORMAT = 0x31
    var ADXL345_BW_RATE = 0x2C

    var addr = 0
    var w = tasmota.wire_scan(ADXL345_ADDR1)
    if w == nil
      w = tasmota.wire_scan(ADXL345_ADDR2)
      if w == nil
        print(MSG + 'ADXL345 not found')
        return nil
      else
        addr = ADXL345_ADDR2
      end
    else
      addr = ADXL345_ADDR1
    end

    # Check device ID
    var id = w.read_bytes(addr, ADXL345_DEVID, 1)
    if id == nil || id.size() == 0
      print(MSG + 'ADXL345: Failed to read DEVID')
      return nil
    end
    if id[0] != 0xE5
      print(MSG + 'ADXL345: Invalid DEVID: 0x' + string.hex(id[0]))
      return nil
    end
    print(MSG + 'ADXL345 found at 0x' + string.hex(addr))

    # Set data format: full resolution, ±2g
    # 0x08 = 0000 1000 -> FULL_RES=1, range=00 (±2g)
    w.write_bytes(addr, ADXL345_DATA_FORMAT, bytes().add(0x08, 1))
    tasmota.delay(1)

    # Set output data rate to 100 Hz (0x0A)
    # 0x0A = 100 Hz, 0x0B = 200 Hz, etc.
    w.write_bytes(addr, ADXL345_BW_RATE, bytes().add(0x0A, 1))
    tasmota.delay(1)

    # Enable measurement
    w.write_bytes(addr, ADXL345_POWER_CTL, bytes().add(0x08, 1))
    tasmota.delay(1)

    print(MSG + 'ADXL345 configured (full resolution, ±2g, 100Hz)')
    return [addr, w]
  end

  # Read accelerometer from ADXL345
  # Returns: [ax, ay, az] in g units or nil on failure
  def adxl345_read_accel(addr, w)
    var ADXL345_DATAX0 = 0x32   # X-axis data low byte
    # Read 6 bytes (X low, X high, Y low, Y high, Z low, Z high)
    var d = w.read_bytes(addr, ADXL345_DATAX0, 6)
    if d == nil || size(d) != 6
      print(MSG + 'ADXL345: Failed to read accelerometer data')
      return nil
    end

    # Helper: convert little-endian (low byte first) to signed int16
    def to_i16(l, h)
      var v = (h << 8) | l
      if v > 32767
        v -= 65536
      end
      return v
    end

    # Scale factor: ADXL345 full resolution sensitivity = 256 LSB/g
    var scale = 256.0

    return [
      to_i16(d[0], d[1]) / scale,
      to_i16(d[2], d[3]) / scale,
      to_i16(d[4], d[5]) / scale
    ]
  end


  class LEVEL
    #
    var w              # Wire/I2C object (passed in, not scanned)
    var addr           # I2C address
    # Calibration vector - the normalized gravity vector when device is level
    var cal_x
    var cal_y
    var cal_z
    var calibrated
    # Tilt monitor
    var read_accel # Points to one of the above functions QMI MPU6050 etc
    var tilt_callback
    var tilt_max_angle # in degrees
    var interval # Interval for tilt monitor in ms
    static PERSIST_KEY = 'calibration'

    def init(addr,w, read_accel)
      # wire: tasmota wire_scan result (already validated)
      # addr: I2C address
      if addr==nil || w == nil || read_accel==nil
        print('level.init() needs addr, w, read_accel')
        return
      end
      self.cal_x = 0.0
      self.cal_y = 0.0
      self.cal_z = 1.0
      self.calibrated = false
      self.w = w
      self.addr = addr
      self.read_accel = read_accel
      # Try to load saved calibration
      self._load_calibration()
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
        persist.save()
        print('The flash data are invalid. Run level.calibrate() again')
      end
    end

    # Internal: save calibration to flash
    def _save_calibration()
      if !self.calibrated
        print('Not calibrated yet')
        return false
      end
      var cal = [self.cal_x, self.cal_y, self.cal_z]
      persist.setmember(LEVEL.PERSIST_KEY, cal)
      persist.save()
      print(MSG + 'Calibration saved to flash')
    end

    # Get total tilt angle in radians
    def tilt_rad()
      if !self.calibrated
        print(MSG + 'Warning: Not calibrated. Run: level.calibrate()')
        return nil
      end
      var a = self.read_accel(self.addr, self.w)
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
      if samples == nil samples = 10 end
      print(MSG + 'Calibrating... keep steady (' .. samples .. ' samples)')
      var sum_x = 0.0
      var sum_y = 0.0
      var sum_z = 0.0
      var i = 0
      while i < samples
        var a = self.read_accel(self.addr, self.w)
        if a != nil
          sum_x += a[0]
          sum_y += a[1]
          sum_z += a[2]
          i += 1
        end
        tasmota.yield()
        tasmota.delay(5)
      end
      # Normalize to unit vector
      var len = math.sqrt(sum_x*sum_x + sum_y*sum_y + sum_z*sum_z)
      if len < 0.1
        print(MSG + 'Error: Invalid calibration')
        return
      end
      # Use set_calibration to normalize and set (avoids duplicate code)
      var cal_vector = [sum_x / len, sum_y / len, sum_z / len]
      self.set_calibration(cal_vector)
      # Save to flash
      self._save_calibration()
    end # calibrate(..)

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
    end # set_calibration(..

    # Helper: radians to degrees
    def _deg(rad)
      if rad == nil return nil end
      return rad * 180.0 / math.pi
    end

    # Get total tilt angle in degrees (most common use)
    def tilt()
      return self._deg(self.tilt_rad())
    end

    def tilt_monitor(callback, interval) # action to be triggered, interval in ms
      tasmota.remove_timer(self)
      if interval == nil interval = 100 end
      self.interval = interval
      if type(interval) != 'int' || interval<=0
        print('Wrong value for interval, must be ms')
        return
      end
      if type(callback)!='function'
        print('Callback must be a function')
        return
      end
      self.tilt_callback = callback
      print("Starting tilt monitor")
      self._tilt()
    end # tilt_monitor(..)

    def stop_tilt_monitor()
      if self.tilt_callback
        self.tilt_callback = nil
        print('Tilt monitor is stopped')
      end
      tasmota.remove_timer(self)
    end

    def _tilt()
      if !self.tilt_callback
        print('Bug, _tilt() called with no callback')
        return
      end
      var t = self.tilt()
      if t>10
        print("Tilt detected") # monitor is stopped, it needs to reenable
        var cb = self.tilt_callback
        self.tilt_callback = nil
        cb(t)
      else
        tasmota.set_timer(self.interval, /->self._tilt(), self)
      end
    end # _tilt()

    def deinit()
      # We need the message to know if BerryVM removes the old instance(on reload)
      print(self, '.deinit()')
    end

  end # end of LEVEL class

  # Scan for the connected accelerometer (var imu) one by one
  var imu
  #
  imu = qmi8658_init()
  if imu != nil
    level = LEVEL(imu[0], imu[1], qmi8658_read_accel)
    return level
  end
  #
  imu = mpu6050_init()
  if imu != nil
    level = LEVEL(imu[0], imu[1], mpu6050_read_accel)
    return level
  end
  #imu = mma8452_init()
  #  if imu != nil
  #  level = LEVEL(imu[0], imu[1],mma8452_read_accel)
  #  return level
  #end
  imu = lsm6ds3_init()
  if imu != nil
    level = LEVEL(imu[0], imu[1], lsm6ds3_read_accel)
    return level
  end
  imu = adxl345_init()
  if imu != nil
    level = LEVEL(imu[0], imu[1], adxl345_read_accel)
    return level
  end
  imu = bmi160_init()
  if imu != nil
    level = LEVEL(imu[0], imu[1], bmi160_read_accel)
    return level
  end
  print(MSG + 'No supported IMU module found. Supported: QMI8658, MPU6050, LSM6DS3, ADXL345, BMI160')
  return nil

end # EOF
