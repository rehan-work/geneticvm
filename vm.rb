require 'pp'
require './vm/translation'

DEBUG_MODE = false
MAGIC_NUMBER = 99.0
REG_SIZE = 2

MANGLE_UNCHANGED_INPUT = 9000

class UnimplementedOpcode < StandardError
end

class VM

  include VirtualMachine::Translation

  def initialize(registers=[], flags=[])
    initialize_registers(registers)
    @debug = DEBUG_MODE
    set_flags(flags)
    @pc = 0
  end

  def enable_debug!
    @debug = true
  end

  def translate
    Compiler.new(@mem).translate_rb
  end

  def set_flags(flags)
    @flags = flags
  end

  def enabled?(flag)
    (@flags.include?(flag))
  end

  def initialize_registers(registers)
    @r = registers.map(&:to_f) + Array.new(REG_SIZE, 1.0) + (0..255).to_a
#    Array.new(REG_SIZE-registers.size, -> { initial_register_value })
  end

  def initial_register_value
    0.0
  end

  def next_executable_instruction
    begin
      return @mem[@pc, @mem.size].zip(0..@mem.size-1).select { |instr| instr[0][0] < 12 }.map { |i| i[1] }.first(1)[0] + 1
    rescue
      return @pc+1
    end
#    z = @mem[@pc, @mem.size].zip(0..@mem.size)
#    .select { |instr| instr[0] }
#    .select { |instr| (0..11).include?(instr[0][0]) && instr[1] > @pc }
#    .first(1)[0][0][0]
  end

  def ops(n)
    ops = []
    ops[0] = -> (op, r1, r2, r3) { 1 }
    ops[1] = -> (op, r1, r2, r3) { @r[r1] = (@r[r2] + @r[r3]); }
    ops[2] = -> (op, r1, r2, r3) { @r[r1] = @r[r2] - @r[r3]; }
    ops[3] = -> (op, r1, r2, r3) { @r[r1] = @r[r2] * @r[r3]; }
    ops[4] = -> (op, r1, r2, r3) { 
      if @r[r3] == 0
        @r[r1] = @r[r2] + MAGIC_NUMBER
      else
        @r[r1] = @r[r2] / @r[r3]; 
      end
    }
    ops[5] = -> (op, r1, r2, r3) { 
      if @r[r3].abs <= 10
        @r[r1] = (@r[r2] ** @r[r3].abs) 
      else
        @r[r1] = @r[r2] + MAGIC_NUMBER
      end
    }
    ops[6] = -> (op, r1, r2, r3) { 
     if @r[r2] <= 32
       @r[r1] = Math.exp(@r[r2]);  
     else
       @r[r1] = @r[r2] + MAGIC_NUMBER
     end
    }
    ops[7] = -> (op, r1, r2, r3) { 
      if @r[r2] == 0
        @r[r1] = Math.log(@r[r2]); 
      else
       @r[r1] = @r[r2] + MAGIC_NUMBER
      end
    }
    ops[8] = -> (op, r1, r2, r3) { @r[r1] = (@r[r2]**2);  }
    ops[9] = -> (op, r1, r2, r3) { 
      @r[r1] = Math.sqrt(@r[r2].abs); 
    } 
    ops[10] = -> (op, r1, r2, r3) { 
      @r[r1] = Math.sin(@r[r2]) 
    }
    ops[11] = -> (op, r1, r2, r3) { 
      @r[r1] = Math.cos(@r[r2]) 
    }
    ops[12] = -> (op, r1, r2, r3) { (@r[r2] > @r[r3]) ? @pc += 0 : @pc = next_executable_instruction}
    ops[13] = -> (op, r1, r2, r3) { (@r[r2] <= @r[r3]) ? @pc += 0 : @pc = next_executable_instruction}
    ops[14] = -> (op, r1, r2, r3) { (@r[r2]) ? @pc += 0 : @pc = next_executable_instruction}
    ops[15] = -> (op, r1, r2, r3) { @r[r1] = @r[r2].to_i ^ @r[r3].to_i }
    ops[16] = -> (op, r1, r2, r3) { @r[r1] = @r[r2].to_i | @r[r3].to_i }
    ops[n]
  end

  def debug(op_code, r1, r2, r3)

    return if @debug == false

    case op_code
      when 0
        puts "#{@pc} NOOP"
      when 1
        puts "#{@pc} r#{r1} = r#{r2} + r#{r3}"
      when 2
        puts "#{@pc} r#{r1} = r#{r2} - r#{r3}"
      when 3
        puts "#{@pc} r#{r1} = r#{r2} * r#{r3}"
      when 4
        puts "#{@pc} r#{r1} = r#{r2} / r#{r3}"
      when 5
        puts "#{@pc} r#{r1} = r#{r2} ** r#{r3}"
      when 6
        puts "#{@pc} r#{r1} = EXP(r#{r2})"
      when 7
        puts "#{@pc} r#{r1} = LOG(r#{r2})"
      when 8
        puts "#{@pc} r#{r1} = r#{r2} ** 2"
      when 9
        puts "#{@pc} r#{r1} = r#{r2} ^ 1/2"
      when 9
        puts "#{@pc} r#{r1} = SIN(r#{r2})"
      when 10
        puts "#{@pc} r#{r1} = COS(r#{r2})"
      when 11        
        puts "IF (R#{r2} > R#{r3})"
      when 12
        puts "IF (R#{r2} < R#{r3})"
      when 13
        puts "IF (R#{r3})"
      when 14
        puts "IF (R#{r3})"
      when 15
        puts "R#{r1} = R#{r2} ! R#{r3}"
      when 16
        puts "R#{r1} = R#{r2} ^ R#{r3}"
      else
        puts "Invalid Opcode"
      end
  end

  def final_instruction?
    @pc >= @mem.size
  end

  def fetch
    @mem[@pc]
  end

  def run

    running = true
    set_initial_r0
    start_exec_timer

    if @mem.size == 0
      @r[0] = MAGIC_NUMBER
      return @r
    end

    while running

      if check_exec_timer
        @r[0] = MAGIC_NUMBER + rand(0..99)
        break
      end

      break if final_instruction?

      op_code, r1, r2, r3 = fetch # fetch the next instruction from memory
#      r1, r2, r3 = r1.abs.to_i, r2.abs.to_i, r3.abs.to_i
      instr_nil_check!([op_code, r1, r2, r3])

      begin
        ops(op_code).call(op_code, r1, r2, r3)
        debug(op_code, r1, r2, r3)
      rescue TypeError => e
#        mangle_r0! # if the result failed, return a bad value to decrease fitness score
        @r[0] = MAGIC_NUMBER
      rescue ZeroDivisionError => e
#        pp [op_code, r1, r2, r3]
#        mangle_r0! # if the result failed, return a bad value to decrease fitness score
        @r[0] = MAGIC_NUMBER
#         @r[0] = 65535.0
      rescue RangeError => e
        pp [r1, r2, r3].map { |r| @r[r] }
#        pp [op_code, r1, r2, r3]
        @r[0] = MAGIC_NUMBER
      rescue => e
        if e.message.match(/Nil/)
          pp RASM.disasm(@mem)
          exit
        end
        mangle_r0! # if the result failed, return a bad value to decrease fitness score
      end

      @pc += 1 # increment program counter

    end

    set_end_r0 # check the result saved as the return address

    mangle_r0_if_same! # mangle r0 to a bad value if the return value is the same as the initial value

    @r[0] = MAGIC_NUMBER + rand(0..99) if @r[0].class == Float && (@r[0].infinite? || @r[0].nan?)
    @r[0] = MAGIC_NUMBER + rand(0..99) if @r[0].class == Complex
    @r

  end

  def start_exec_timer
    @start_t = Time.now
  end

  def check_exec_timer
    cur_t = Time.now
    total_t = (cur_t - @start_t).abs
    return (total_t > 0.0001)
  end

  def end_exec_timer
    @end_t = Time.now
  end

  def load(code)
    @mem = code
  end

  def set_initial_r0
    @r0_start = @r[0]
  end

  def set_end_r0
    @r0_end = @r[0]
  end

  def mangle_r0!
    @r[0] = MAGIC_NUMBER + rand(0..99)
  end

  def mangle_r0_if_same!
    @r[0] = MAGIC_NUMBER if @r0_start == @r0_end && enabled?(MANGLE_UNCHANGED_INPUT)
  end

  def instr_nil_check!(instr)
    @r[0] = MAGIC_NUMBER if instr.nil?
  end

end
