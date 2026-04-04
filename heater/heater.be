# Heater Safety Controller
# Uses tasmota-level driver for tilt protection

#var heater


while true
  import strict
  import gpio
  #import level
  if global.level == nil
    print('HEATER: level driver not loaded (no IMU detected). Check wiring.')
    return nil
  end

  # it will performed only on "load('level')"
  # when developing the heater code
  #try
    if global.heater != nil
      global.heater.cleanup()
      global.heater = nil
      tasmota.gc()
    end
  #except .. as e,m
  #  print(e,m)
  #end

  class PinController
    #
    var pin # The ESP32 pin the LED is connected
    var t1, t2 # ON,OFF time
    var ON, OFF # = gpio.HIGH/LOW. If led is inverted LOW/HIGH
    var off_time_millis
    #
    def init(pin, inverted) # pass inverted = true for active low LEDs
      if type(pin) != 'int' print('pin is incorrect') return end
      self.pin = pin
      if inverted
          self.ON = gpio.LOW
          self.OFF = gpio.HIGH
      else
          self.ON = gpio.HIGH
          self.OFF = gpio.LOW
      end
      gpio.pin_mode(self.pin, gpio.OUTPUT)
      gpio.digital_write(self.pin, self.OFF) # We start with the LED -> OFF
    end
    
    def blink(duration, t1, t2)
      tasmota.remove_timer(self)
      if type(duration) != 'int' # || duration <=0
        return "duration incorrect"
      end
      if type(t1)!='int' || t1 <=0
        return "t1 incorrect"
      end
      if t2==nil
        t2=t1
      end
      if type(t2)!='int' || t2 <=0
        return "t2 incorrect"
      end
      if duration>0
        self.off_time_millis = tasmota.millis() + duration
      else
        self.off_time_millis = 0
      end
      self.t1=t1
      self.t2=t2
      self._blink_on()
    end
    
    def on()
      tasmota.remove_timer(self)
      gpio.digital_write(self.pin, self.ON)
    end
    
    def off()
      tasmota.remove_timer(self)
      gpio.digital_write(self.pin, self.OFF)
    end
    
    def _blink_off() # Not to be called by the user
        gpio.digital_write(self.pin, self.OFF)
        if self.off_time_millis>0 && tasmota.millis()>self.off_time_millis
            return # do not set timer -> stop blink
        end
        tasmota.set_timer(self.t2, /-> self._blink_on(), self)      
    end
    
    def _blink_on()
      gpio.digital_write(self.pin, self.ON)
      tasmota.set_timer(self.t1, /-> self._blink_off(), self)
    end

    def cleanup()
      self.stop()
    end
    
    def deinit()
      #self.cleanup()
      # we see the garbage collector in action
      print(self, '.deinit()')
    end
  end # end of PinController

  class HeaterController
    var heater_on # true/false
    var relay
    var led
    var heater_timeout
    var tilt_limit
    var trigger
    
    def init(relay,led)
      self.relay = relay
      self.led = led
      self.heater_timeout = 3600000
      self.tilt_limit = 10
      self.stop()
      # Register button rule
      self.trigger = "Button1#State" #/-> self.button_handler()
      tasmota.add_rule(self.trigger, /-> self.button_handler())
      print("HEATER: Timeout: 1 hour")
    end

    def stop()
      tasmota.remove_timer(self)
      self.relay.off()
      self.led.off()
      level.stop_tilt_monitor()
      if self.heater_on
        print('Heater is stopped')
      end
      self.heater_on = false
    end
    
    # Start heater
    def start()
      # Check if device is tilted before starting
      var current_tilt = level.tilt()
      if current_tilt == nil
        print('HEATER: Cannot start - level sensor not calibrated')
        return
      end
      if current_tilt > self.tilt_limit
        print('HEATER: Cannot start - device is tilted (' + str(current_tilt) + '°)')
        return
      end
      tasmota.remove_timer(self)
      self.relay.on()
      self.led.on()
      tasmota.set_timer(self.heater_timeout, /-> self.stop(), self)
      level.tilt_monitor(/-> self._tilt_trigger())
      if !self.heater_on
        print('Heater is started')
      end
      self.heater_on = true
    end
    
    def _tilt_trigger() # internal
      self.stop()
      self.led.blink(10000,200)
    end

    # Button handler - toggles heater
    def button_handler()
      if self.heater_on
        self.stop()
      else
        self.start()
      end
    end

    def cleanup()
      self.stop()
      print("Removing button rule")
      tasmota.remove_rule(self.trigger)
    end
    
    def deinit()
      print(self,'.deinit()')
    end
  end

  var relay_pin = gpio.pin(gpio.INTERRUPT,0)
  if relay_pin<0
    print("Set the relay pin as INTERRUPT-0")
    break
  end
  var led_pin = gpio.pin(gpio.INTERRUPT,1)
  if led_pin<0
    print("Set the led pin as INTERRUPT-1")
    break
  end
  if gpio.pin(gpio.I2C_SDA,0)<0
    print('Set the IMU I2C_SDA-0 pin in config ')
  end
  if gpio.pin(gpio.I2C_SCL,0)<0
    print('Set the IMU I2C_SCL-0 pin in config')
  end
  if gpio.pin(gpio.KEY1,0)<0
    print('Set the Button-0 pin in config')
    break
  end

  if !level.calibrated
    print('Calibrate the level driver with level.calibrate() first')
  end

  var relay = PinController(relay_pin)
  var led = PinController(led_pin)

  # Create global instance when used with load('level')
  global.heater = HeaterController(relay, led)
  # when used with 'import level'
  # import is performed only once (ensured by the berry intrepreter)
  return global.heater 
end
