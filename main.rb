# encoding: utf-8

require "bundler/setup"
require "gaminator"

$debuglog = File.new("log.log", "w+")
$stack=[]
$unmarked = true
class WalkerGame
  class EmptyTile < Struct.new(:x, :y)
    @marked = false
    attr_accessor :marked

    def char
      ""
    end

    def blocking?
      return false
    end


    def winning?
      false
    end
  end

  class Tile < Struct.new(:x, :y)
    @pl = []

    def bl(x, y)
      if something = $gmap.get(x, y)
        return true if something.blocking?
        return false
      end
    end

    def each_neighbor
      x=self.x
      y=self.y
      pr=[]
      if !bl(x-1, y)
        pr.push [self.x-1, self.y]
      end
      if !bl(x+1, y)
        pr.push [self.x+1, self.y]
      end
      if !bl(x, y-1)
        pr.push [self.x , self.y-1]
      end
      if !bl(x, y+1)
        pr.push [self.x , self.y+1]
      end
      pr.sort {|x,y| (  ((y[0]-$fin_x).abs+(y[1]-$fin_y).abs)   <=> (x[0]-$fin_x).abs+(x[1]-$fin_y).abs)}
      $debuglog.puts "TUTUTUTUTU"
      $debuglog.puts pr
      pr.each {|o|
        yield o[0],o[1]
      }
    end
  end

  class Player < Struct.new(:x, :y)
    @marked = false
    attr_accessor :marked
    attr_accessor :last_x
    attr_accessor :last_y

    def char
      "@"
    end

    def color
      Curses::COLOR_RED
    end

    def move(x, y)
      self.x+=x
      self.y+=y
    end

    def shoot
      b = Bullet.new(self.x, self.y)
      b.dir_x = @last_x
      b.dir_y = @last_y
      $gmap.objects << b
      $gmap.bullets << b
    end

  end

  class Item < Struct.new(:x, :y)
    @marked = false
    attr_accessor :marked

    def blocking?
      false
    end

    def winning?
      false
    end
  end

  class Monster < Item
    def char
      'X'
    end

    def color
      Curses::COLOR_GREEN
    end

    def move(x, y)
      $debuglog.puts "MONSTER: Moving from #{self.x},#{self.y} TO #{self.x+x},#{self.y+y}"
      self.x+=x
      self.y+=y
    end

  end

  class Wall < Item
    def char
      '#'
    end

    def blocking?
      true
    end
  end

  class Bullet < Item
    attr_accessor :dir_x
    attr_accessor :dir_y
    def char
      '*'
    end

    def color
      Curses::COLOR_YELLOW
    end

    def direction(x,y)
      @dir_x = x
      @dir_y = y
    end

    def blocking?
      false
    end

    def move(x, y)
      self.x+=@dir_x
      self.y+=@dir_y
    end
  end

  class Finish < Item
    def char
      'F'
    end

    def winning?
      true
    end

    def color
      Curses::COLOR_BLUE
    end
  end

  class Start < Item
    def char
      ''
    end
  end

  class Map < Hash
    attr_accessor :types
    attr_accessor :objects
    attr_accessor :bullets
    OBJECT_MAPPING = {
        '#' => Wall,
        "S" => Start,
        "F" => Finish,
        "X" => Monster,
        " " => EmptyTile
    }

    def get(x, y)
      self[x][y] if self[x]
    end

    def delete(x,y)
      self[x].delete(y) if self[x]
    end

    def set(x, y, value)
      self[x] = {} unless self[x]
      self[x][y] = value
    end

    def load_map(file)
      @objects = []
      @bullets = []
      @types = {}
      file = File.open(file)
      y = 0
      file.each_line do |line|
        x = 0
        line.chomp.each_char do |char|
          self.resolve_object(char, x, y)
          if (char == 'F')
            puts "RZYG"
            $fin_x = x
            $fin_y = y
          end
          x += 1
        end
        y += 1
      end
    end

    def resolve_object(char, x, y)
      if klass = OBJECT_MAPPING[char]
        instance = klass.new(x, y)
        self.set(x, y, instance)
        @objects.push instance
        name = klass.name.split('::').last
        @types[name] ||= []
        @types[name].push(instance)
      end
    end

    def unmark_all
      if @map
        @monsters.each { |m| m.marked = false }
        @player.marked = false
      end
      $debuglog.puts "UNMARKING ..."
      $debuglog.puts self.length
      $debuglog.puts self[0].length
      if $unmarked==false
        @objects.each { |obj|
          obj.marked = false
        }
      end
    end

  end

  def initialize(width, height)
    @ticks = 0
    @width = width
    @height = height
    @score = 0
    @map = Map.new
    $gmap = @map
    @map.load_map File.join(File.dirname(__FILE__), "map.txt")
    puts @map.types.keys
    start = @map.types['Start'].first
    monster = @map.types['Monster'].first
    @monsters = []
    @monsters << Monster.new(monster.x, monster.y)
    @player = Player.new(start.x, start.y)
    reset_speed
  end

  def wait?
    false
  end


  def shoot
    @player.shoot
  end

  def reset_speed
    @speed = 0
  end

  def tick
    #$debuglog.puts "TICK #{@ticks}"
    if !($fin_x.nil?)
      #$debuglog.puts "Chasing #{$fin_x} #{$fin_y}"
      chase(@monsters[0], @map.get($fin_x, $fin_y))
    end
    if !($gmap.bullets.nil?)
      $gmap.bullets.each { |b|
        $debuglog.puts "Bullet #{b.class} context #{self.class}"
        move(b, b.dir_x, b.dir_y)
      }
    end
    increase_tick_count
  end

  def increase_tick_count
    @ticks += 1
  end

  def input_map
    {
        "a" => :move_left,
        "w" => :move_top,
        "s" => :move_down,
        "d" => :move_right,
        "q" => :quit,
        "x" => :shoot
    }
  end

  def quit
    exit
  end


  def dfs(tile, p, tarx, tary)
    $debuglog.puts "DFS: #{tile.x},#{tile.y} || Target = #{tarx} #{tary}"
    if (tile.x>0 && tile.y>0 && $stack.length==0)
      if (@map.get(tile.x, tile.y))
        if ((tile.x - tarx).abs+(tile.y - tary).abs == 0)
          $stack = p+[tile.x, tile.y]
          @map.unmark_all
          return
        end
        if ($stack.length==0)
          @map.get(tile.x, tile.y).marked=true
          $unmarked = false
          tile.each_neighbor { |x, y|
            $debuglog.puts "DFS neighbor: #{x},#{y} | CLASS #{@map.get(x, y)}"
            $debuglog.puts "DFSmark#{$stack.length}: #{x},#{y} #{@map.get(x, y).marked}"
            if (@map.get(x, y) && @map.get(x, y).marked!=true)
              dfs(Tile.new(x, y), p+[x, y], tarx, tary)
            end

          }
        end
      end
    end

  end

  def chase(i1, i2)
    #i1 follows i2
    if ((i1.x-i2.x).abs>1||(i1.y-i2.y).abs>1)
      if $stack.length>1
        #$debuglog.puts "SUCCSTACK #{$stack}"
        move(i1, $stack[0]-i1.x, $stack[1]-i1.y)
        $stack = $stack[2..$stack.length]
        return
      end
      sp = Tile.new(i1.x, i1.y)
      successqueue = dfs(sp, [], i2.x, i2.y)
      @map.get(i1.x, i1.y).marked=false
    else
      $stack = []
      @status = "You lose! BAD DFS had score #{@ticks}"
      exit
      @map.unmark_all
    end
  end

  def move_right
    @player.last_x = 1
    @player.last_y = 0
    move @player, 1, 0 if @player.y < @width - 1
  end

  def move_left
    @player.last_x = -1
    @player.last_y = 0
    move @player, -1, 0 if @player.x > 0
  end

  def move_top
    @player.last_x = 0
    @player.last_y = -1
    move @player, 0, -1 if @player.y > 0
  end

  def move_down
    @player.last_x = 0
    @player.last_y = 1
    move @player, 0, 1 if @player.y < @height - 1
  end

  def move(inst, x, y)
    new_x, new_y = inst.x + x, inst.y + y
    if something = @map.get(new_x, new_y)
      if something.blocking?
        if inst.instance_of? Bullet
          $gmap.objects.delete($gmap.get(new_x, new_y))
          $gmap.objects.delete(inst)
          $gmap.bullets.delete(inst)
          $gmap.delete(something.x,something.y)
          #$GAME.delete(inst)
          return
        else
          return
        end
      end
      finish if something.winning?
    end
    inst.move x, y
  end

  def objects
    [@player] + @map.objects + @monsters
  end

  def finish
    @status = "Win! Score is #{@ticks}"
    exit
  end

  def textbox_content
    ""
  end

  def exit
    Kernel.exit
  end

  def exit_message
    @status
  end


  def sleep_time
    0.0001
  end

end

$GAME = Gaminator::Runner.new(WalkerGame).run