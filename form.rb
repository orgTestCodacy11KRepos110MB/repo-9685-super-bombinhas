require_relative 'global'
include MiniGL

class FormSection
  attr_reader :cur_btn

  def initialize(components)
    @components = components
    @buttons = []
    @components.each do |c|
      @buttons << c if c.is_a? Button
    end
    @visible = false
    @changing = nil
    @cur_btn = @buttons[@cur_btn_index = 0]
  end

  def update(mouse_moved)
    return if @changing
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
    elsif KB.key_pressed?(Gosu::KbReturn) or KB.key_pressed?(Gosu::KbSpace)
      @cur_btn.click
    end
    @cur_btn = @buttons[@cur_btn_index]
  end

  def show
    @visible = true
    @changing = nil
  end

  def hide
    @visible = false
    @changing = 0
  end

  def draw
    @components.each { |c| c.draw } if @visible
  end
end

class Form
  attr_reader :cur_section_index

  def initialize(*section_components)
    @sections = []
    section_components.each do |c|
      @sections << FormSection.new(c)
    end
    @highlight_alpha = 102
    @highlight_state = 0
    @cur_section = @sections[@cur_section_index = 0]
    @cur_section.show
  end

  def update
    mouse_moved = Mouse.x != @mouse_prev_x || Mouse.y != @mouse_prev_y
    @mouse_prev_x = Mouse.x
    @mouse_prev_y = Mouse.y

    @cur_section.update(mouse_moved) # @sections.each { |s| s.update(mouse_moved) }

    update_highlight
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

  def draw
    @cur_section.draw # @sections.each { |s| s.draw }
    draw_highlight
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