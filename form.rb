require_relative 'global'
include MiniGL

module FormElement
  attr_reader :x, :y, :start_x, :start_y

  def init_movement
    @start_x = @x
    @start_y = @y
  end

  def move_to(x, y)
    @aim_x = x
    @aim_y = y
  end

  def update_movement
    if @aim_x
      dist_x = @aim_x - @x
      dist_y = @aim_y - @y
      if dist_x.round == 0 and dist_y.round == 0
        @x = @aim_x
        @y = @aim_y
        @aim_x = @aim_y = nil
      else
        set_position(@x + dist_x / 5.0, @y + dist_y / 5.0)
      end
    end
  end
end

class MenuText
  include FormElement

  attr_accessor :text

  def initialize(text, x, y, width = 760, mode = :justified)
    @text = text
    @x = x
    @y = y
    @width = width
    @mode = mode
    @writer = TextHelper.new SB.font, 5
  end

  def update; end

  def set_position(x, y)
    @x = x; @y = y
  end

  def draw
    @writer.write_breaking(@text, @x, @y, @width, @mode)
  end
end

class MenuButton < Button
  include FormElement

  def initialize(y, text_id, x = 310, &action)
    super(x, y, SB.font, SB.text(text_id), :ui_button1, 0, 0x808080, 0, 0, true, false, 0, 7, 0, 0, 0, &action)
  end
end

class MenuTextField < TextField
  include FormElement
end

class FormSection
  attr_reader :cur_btn, :changing

  def initialize(components, visible = false)
    @components = components
    @buttons = []
    @components.each do |c|
      @buttons << c if c.is_a? Button
      c.init_movement
      c.set_position(c.x - C::SCREEN_WIDTH, c.y) unless visible
    end
    @visible = visible
    @changing = nil
    @cur_btn = @buttons[@cur_btn_index = 0]
  end

  def update(mouse_moved)
    if @changing
      @components.each do |c|
        if c.update_movement.nil?
          @visible = false if @changing == 0
          @changing = nil
        end
      end
    elsif @visible
      @components.each { |c| c.update }
      @buttons.each_with_index do |b, i|
        if b.state == :down || mouse_moved && b.state == :over
          @cur_btn_index = i
          break
        end
      end
      if KB.key_pressed? Gosu::KbDown or KB.key_pressed? Gosu::KbRight
        @cur_btn_index += 1
        @cur_btn_index = 0 if @cur_btn_index == @buttons.length
      elsif KB.key_pressed? Gosu::KbUp or KB.key_pressed? Gosu::KbLeft
        @cur_btn_index -= 1
        @cur_btn_index = @buttons.length - 1 if @cur_btn_index < 0
      elsif KB.key_pressed?(Gosu::KbReturn)
        @cur_btn.click
      end
      @cur_btn = @buttons[@cur_btn_index]
    end
  end

  def show
    @visible = true
    @changing = 1
    @components.each { |c| c.move_to(c.start_x, c.y) }
  end

  def hide
    @changing = 0
    @components.each { |c| c.move_to(c.x - C::SCREEN_WIDTH, c.y) }
  end

  def clear
    @components.clear
    @buttons.clear
  end

  def reset
    @cur_btn = @buttons[@cur_btn_index = 0]
  end

  def add(component)
    @components << component
    if component.is_a? Button
      @buttons << component
      @cur_btn = @buttons[@cur_btn_index = 0] if @cur_btn.nil?
    end
    component.init_movement
    component.set_position(component.x - C::SCREEN_WIDTH, component.y) unless @visible
  end

  def draw
    @components.each { |c| c.draw } if @visible
  end
end

class Form
  attr_reader :cur_section_index

  def initialize(*section_components)
    @sections = [FormSection.new(section_components.shift, true)]
    section_components.each do |c|
      @sections << FormSection.new(c)
    end
    @highlight_alpha = 102
    @highlight_state = 0
    @cur_section = @sections[@cur_section_index = 0]
    # @cur_section.show
  end

  def update
    mouse_moved = Mouse.x != @mouse_prev_x || Mouse.y != @mouse_prev_y
    @mouse_prev_x = Mouse.x
    @mouse_prev_y = Mouse.y

    @sections.each { |s| s.update(mouse_moved) }
    update_highlight unless @cur_section.changing
  end

  def update_highlight
    if @highlight_state == 0
      @highlight_alpha += 3
      @highlight_state = 1 if @highlight_alpha == 255
    else
      @highlight_alpha -= 3
      @highlight_state = 0 if @highlight_alpha == 102
    end
  end

  def go_to_section(index)
    @cur_section.hide
    @cur_section = @sections[@cur_section_index = index]
    @cur_section.show
  end

  def section(index)
    @sections[index]
  end

  def reset
    @sections.each { |s| s.reset }
    go_to_section 0
  end

  def draw
    @sections.each { |s| s.draw }
    draw_highlight unless @cur_section.changing
  end

  def draw_highlight
    btn = @cur_section.cur_btn
    x = btn.x; y = btn.y; w = btn.w; h = btn.h
    (1..4).each do |n|
      color = ((@highlight_alpha * (1 - (n-1) * 0.25)).round) << 24 | 0xffff00
      G.window.draw_line x - n, y - n + 1, color, x + w + n - 1, y - n + 1, color
      G.window.draw_line x - n, y + h + n, color, x + w + n, y + h + n, color
      G.window.draw_line x - n + 1, y - n + 1, color, x - n + 1, y + h + n - 1, color
      G.window.draw_line x + w + n, y - n, color, x + w + n - 1, y + h + n - 1, color
    end
  end
end