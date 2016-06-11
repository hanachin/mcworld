require 'pry'
require_relative 'mc_world/world'
infile='/Users/tomoya/Library/Application Support/minecraft/saves/command/region/r.0.0.mca'
outfile='/Users/tomoya/Library/Application Support/minecraft/saves/rubytest/region/r.0.0.mca'
exworld = MCWorld::World.new file: infile
exworld[13,8,71]
exworld.pry
class Computer
  VALUE_BITS = 32
  MEM_ADDRESS = {x: 0, y: 0, z: 128}
  SEEK_GET = {x: 0, y:128, z:128}
  SEEK_SET = {x: 1, y:128, z:128}
  MEM_REF = {x: 2, y: 128, z: 128}
  MEM_VALUE = {x:3, y: 128, z: 128}
  OP_DONE = {x:4, y:128, z: 128}
  DISPLAY = {x: 0, y:0, z:0, cw: 5, ch: 8, wn: 24, hn: 12}
  def initialize
    @world = MCWorld::World.new x: 0, z: 0
    Internal.prepare @world
  end

  def mem_direct_set_command addr, src: MEM_VALUE
    pos = Internal.mem_addr_coord addr
    [
      :clone,
      "#{src[:x]} #{src[:y]} #{src[:z]}",
      "#{src[:x]} #{src[:y]} #{src[:z]+VALUE_BITS}",
      "#{addr[:x]} #{addr[:y]} #{addr[:z]}"
    ].join ' '
  end

  def mem_direct_get_command addr, dst: MEM_VALUE
    pos = Internal.mem_addr_coord addr
    [
      :clone,
      "#{pos[:x]} #{pos[:y]} #{pos[:z]}",
      "#{pos[:x]} #{pos[:y]} #{pos[:z]+VALUE_BITS}",
      "#{dst[:x]} #{dst[:y]} #{dst[:z]}"
    ].join ' '
  end
  def mem_op_begin_command mode
    pos, size = Internal.seek_blocks_info mode
    [
      :clone,
      "#{pos[:x]} #{pos[:y]} #{pos[:z]}",
      "#{pos[:x]} #{pos[:y]} #{pos[:z]+size-1}",
      "#{MEM_ADDRESS[:x]} #{MEM_ADDRESS[:y]} #{MEM_ADDRESS[:z]-size}"
    ].join ' '
  end
  def mem_op_set_callback_command pos
    pos, size = Internal.seek_blocks_info mode
    [
      :clone
      "#{pos[:x]} #{pos[:y]} #{pos[:z]}",
      "#{pos[:x]} #{pos[:y]} #{pos[:z]}",
      "#{MEM_ADDRESS[:x]} #{MEM_ADDRESS[:y]} #{MEM_ADDRESS[:z]-size+1}"
    ].join ' '
  end
  def mem_op_execute_command
    "setblock #{MEM_ADDRESS[:x]} #{MEM_ADDRESS[:y]} #{MEM_ADDRESS[:z]-1} redstone_block"
  end

  module Internal
    def self.command_data command, powered: false,
      {
        'conditionMet' => MCWorld::Tag::Byte.new(0),
        'auto' => MCWorld::Tag::Byte.new(0),
        'customName' => MCWorld::Tag::String.new('@'),
        'auto' => MCWorld::Tag::Byte.new(0),
        'powered' => MCWorld::Tag::Byte.new(powered ? 1 : 0),
        'Command' => MCWorld::Tag::String.new(command),
        'id' => MCWorld::Tag::String.new('Control'),
        'SuccessCount' => MCWorld::Tag::Int.new(0),
        'TrackOutput' => MCWorld::Tag::Int.new(0),
      }
    end
    def self.gen_seek_blocks mode
      raise 'mode get/set' unless [:get, :set].include? mode
      size = 1+7*12+12+2
      blocks = []
      x, y, z = MEM_REF[:x], MEM_REF[:y], MEM_REF[:z]
      memz = MEM_ADDRESS[:z]
      vx, vy, vz = MEM_VALUE[:x], MEM_VALUE[:y], MEM_VALUE[:z]
      add = ->(command, chain: false, cond: false){
        unless command
          blocks << nil
          next
        end
        block = (chain ? MCWorld::Block::ChainCommandBlock : MCWorld::Block::CommandBlock)
        data = MCWorld::Block::Data::Z_MINUS | (cond ? 0 : MCWorld::Block::DATA::MASK)
        blocks << = [block[data], command_data(command)]
      }
      add[nil]
      7.times{|i|
        add["testforblock #{x} #{y} #{z+2*i} stone"]
        add["clone ~ ~ #{memz-size} ~ ~ #{memz-1} ~#{1<<i} ~ #{memz-size}", chain: true, cond: true]
        add["setblock ~#{1<<i} ~ ~-3 redstone_block", chain: true, cond: true]
        add["fill ~ ~ #{memz-1} ~ ~ #{memz-size} air", chain: true, cond: true]
        add["setblock ~ ~ ~-3 redstone_block", chain: true]
        add[nil]
        add["testforblock #{x} #{y} #{z+2*i+1} stone"]
        add["clone ~ ~ #{memz-size} ~ ~ #{memz-1} ~ ~#{1<<i} #{memz-size}", chain: true, cond: true]
        add["setblock ~ ~#{1<<i} ~-3 redstone_block", chain: true, cond: true]
        add["fill ~ ~ #{memz-1} ~ ~ #{memz-size} air", chain: true, cond: true]
        add["setblock ~ ~ ~-3 redstone_block", chain: true]
        add[nil]
      }
      4.times{|i|
        add["testforblock #{x} #{y} #{z+14} #{i%2==1 ? 'stone' : 'air'}", chain: true]
        add["testforblock #{x} #{y} #{z+15} #{i/2==1 ? 'stone' : 'air'}", chain: true, cond: true]
        if mode == :get
          add["clone ~ ~ #{memz+VALUE_BITS*i} ~ ~ ~ #{memz+VALUE_BITS*(i+1)} #{vx} #{vy} #{vz} replace", chain: true, cond: true]
        else
          add["clone #{vx} #{vy} #{vz} #{vx} #{vy} #{vz+VALUE_BITS} ~ #{memz+VALUE_BITS*i} replace", chain: true, cond: true]
        end
      }
      add["setblock #{OP_DONE[:x]} #{OP_DONE[:y]} #{OP_DONE[:z]} redstone_block", chain: true]
      add["fill ~ ~ #{memz-1} ~ ~ #{memz-size} air", chain: true]
      blocks.reverse
    end
    def self.seek_get_blocks;@seek_get_blocks||=gen_seek_blocks :get;end
    def self.seek_get_blocks;@seek_set_blocks||=gen_seek_blocks :set;end
    def self.seek_blocks_info mode
      if mode == :get
        [SEEK_GET, seek_get_blocks.size]
      elsif mode == :set
        [SEEK_SET, seek_set_blocks.size]
      end
    end
    def self.prepare world
      (128/16).times.to_a.repeated_permutation{|i,j,k|
        world[i*16+MEM_ADDRESS[:x],j*16+MEM_ADDRESS[:y],k*16+MEM_ADDRESS[:z]]=nil
        world[i*16+15+MEM_ADDRESS[:x],j*16+15+MEM_ADDRESS[:y],k*16+15+MEM_ADDRESS[:z]]=nil
      }
      [[seek_blocks(:get), SEEK_GET], [seek_blocks(:set), SEEK_SET]].each do |block_tile_entities, pos|
        block_tile_entities.each_with_index{|bt, i|
          block, tile_entity = bt
          world[pos[:x],pos[:y],pos[:z]+i] = block
          world.tile_entities[pos[:x],pos[:y],pos[:z]+i] = tile_entity
        }
      }
    end
    def self.mem_addr_coord addr
      x = 0
      y = 0
      z = 0
      7.times{|i|
        x |= (addr>>(1<<(2*i))&1)<<i
        y |= (addr>>(1<<(2*i+1))&1)<<i
      }
      z |= ((addr>>14)&1)<<1
      z |= ((addr>>15)&1)<<2
      {x: MEM_ADDRESS[:x]+x, y: MEM_ADDRESS[:y]+y, z: MEM_ADDRESS[:z]+z}
    end
  end
end

__END__
testforblock bit32 stone
cond clone ~ 64 ~ ~ 128 ~ ~+32 64 ~
cond setblock ~32 ~3 ~ redstone_block
cond fill ~ 64 ~ ~ 128 ~ air
setblock ~ ~+1 ~ restone_block
stone(will be redstone)

8*8
64*

128*128*128

6*7*2
256*256
64*64
data  ptr   code  callback
64bit 14bit 84bit+2bit
val: 16bit 4bit*4

char: 5x8 24x12 120x96


DSL:
label :hoge
var[:x] = var[:x]
var.x
var.y[var.z]=


jump :fuga