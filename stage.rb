# Copyright 2019 Victor David Santos
#
# This file is part of Super Bombinhas.
#
# Super Bombinhas is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Super Bombinhas is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Super Bombinhas.  If not, see <https://www.gnu.org/licenses/>.

require_relative 'section'

class Stage
  attr_accessor :life_count, :star_count
  attr_reader :world, :num, :id, :starting, :cur_entrance, :switches, :spec_taken, :is_bonus, :is_custom,
              :time, :objective, :reward, :won_reward, :stopped, :stopped_timer, :stop_time_duration

  def initialize(world, num)
    @world = world
    @num = num
    @id = "#{world}-#{num}"
    @is_bonus = world == 'bonus'
    @is_custom = world == 'custom'
    @world_name = @is_bonus ? "#{SB.text(:bonus)} #{@num}" : @is_custom ? SB.text(:custom) : SB.text("world_#{@world}")
    @name = @is_bonus ? SB.text("bonus_#{@num}") : @is_custom ? num : "#{@world}-#{@num}: #{SB.text("stage_#{@world}_#{@num}")}"
  end

  def start(loaded = false, time = nil, objective = nil, reward = nil)
    if time
      @time = time
      @counter = 0
      @objective = case objective
                   when 1 then :kill_all
                   when 2 then :get_all_rocks
                   else        :reach_goal
                   end
      @reward = reward
    end

    @warp_timer = 0
    @star_count = 0
    @life_count = 0
    @switches = []
    taken_switches = loaded ? SB.save_data[9].split(',').map(&:to_i) : []
    used_switches = loaded ? SB.save_data[10].split(',').map(&:to_i) : []

    @sections = []
    @entrances = []
    sections = Dir[@is_custom ? "#{SB.save_dir}/levels/#{@num}-*" : "#{Res.prefix}stage/#{@world}/#{@num}-*"]
    sections.sort.each do |s|
      @sections << Section.new(s, @entrances, @switches, taken_switches, used_switches)
    end

    SB.player.set_bombs(@sections[0].bomb_mask)
    SB.player.reset(loaded)
    @cur_entrance = @entrances[loaded ? SB.save_data[7].to_i : 0]
    @cur_section = @cur_entrance[:section]
    if SB.player.startup_item
      @switches << {
        type: Section::ELEMENT_TYPES[SB.player.startup_item],
        x: 0,
        y: 0,
        section: @cur_section,
        state: used_switches.size > 0 ? :used : :taken,
        index: @switches.length
      }
    end

    reset(true)
  end

  def reset(first_time)
    @panel_x = -600
    @timer = 0
    @alpha = 255
    @starting = first_time ? 1 : 2
    @warp_timer = 0
    @star_count = 0
    @spec_taken = false
    @won_reward = false
    @stopped = nil
    @stopped_timer = 0
    reset_switches
    @cur_section.start @switches, @cur_entrance[:x], @cur_entrance[:y]
  end

  def update
    SB.check_song
    if @starting == 1
      @timer = 240 if @timer < 240 && SB.key_pressed?(:confirm)
      if @timer < 240
        @alpha -= 5 if @alpha > 125
      else
        @alpha -= 5 if @alpha > 0
      end
      if @panel_x < 50
        speed = (50 - @panel_x) / 8.0
        speed = 1 if speed < 1
        @panel_x += speed
        @panel_x = 50 if (50 - @panel_x).abs < 1
      elsif @timer < 240
        @panel_x += 0.5
      else
        @panel_x += (@timer - 239)
      end
      @timer += 1
      if @timer == 300
        @starting = 0
      end
    else
      if @starting == 2
        @timer += 1
        if @timer >= 150
          @alpha -= 5
          if @alpha <= 0
            @starting = 0
          end
        end
      end
      if @special_world_warp
        @warp_timer += 1
        if @warp_timer == 30
          @special_world_warp.call
        end
      elsif @warp_timer > 0 && !@cur_section.warp
        @warp_timer -= 1
      end
      return :finish if @time == 0
      status = @cur_section.update(@stopped)
      if status == :finish
        SB.play_sound(Res.sound(:victory), SB.music_volume * 0.1)
        Gosu::Song.current_song.stop
        SB.player.temp_startup_item = get_startup_item if @star_count >= C::STARS_PER_STAGE
        if SB.casual?
          SB.player.score += @reward * 1000 if @reward
        else
          SB.player.lives += @reward if @reward
          SB.player.lives += @life_count
        end
        @won_reward = true
        return :finish
      elsif status == :next_section
        index = @sections.index(@cur_section)
        section = @sections[index + 1]
        if section
          entrance = section.default_entrance || (@entrances.find { |e| e[:section] == section } || @entrances[0])[:index]
          @cur_section.start_warp(entrance)
        end
      elsif SB.player.dead? && @is_bonus
        return :finish
      else
        check_reload
        check_entrance
        check_warp
      end
      if @time
        @counter += 1
        if @counter == 60
          @time -= 1
          @counter = 0
        end
      end
      if @stopped
        @stopped_timer += 1
        if @stopped_timer == @stop_time_duration
          @stopped = nil
        end
      end
    end
  end

  def check_reload
    if @cur_section.reload
      if SB.player.lives >= 0 && SB.player.lives + @life_count == 0
        SB.game_over
      else
        @sections.each do |s|
          s.loaded = false
        end
        SB.player.reset
        @cur_section = @cur_entrance[:section]
        reset(false)
      end
    end
  end

  def check_entrance
    if @cur_section.entrance
      @cur_entrance = @entrances[@cur_section.entrance]
      @cur_section.entrance = nil
      if @is_custom
        SB.save_custom
      else
        SB.save
      end
    end
  end

  def check_warp
    if @cur_section.warp
      @warp_timer += 1
      entrance = @entrances[@cur_section.warp] || @entrances[0]
      section = entrance[:section]
      if @warp_timer > 20 && section.bgm != @cur_section.bgm
        Gosu::Song.current_song.volume = (1 - (@warp_timer - 20).to_f / 10) * 0.1 * SB.music_volume
      end
      if @warp_timer == 30
        @cur_section = section
        if @cur_section.loaded
          @cur_section.do_warp entrance[:x], entrance[:y]
        else
          @cur_section.start @switches, entrance[:x], entrance[:y]
        end
      end
    end
  end

  def special_world_warp(&block)
    @special_world_warp = Proc.new(&block)
  end

  def find_switch(obj)
    @switches.each do |s|
      return s if s[:obj] == obj
    end
    nil
  end

  def find_switches(type)
    @switches.select { |s| s[:type] == type }
  end

  def set_switch(obj)
    switch = self.find_switch obj
    switch[:state] = :temp_taken
  end

  def reset_switches
    @switches.each do |s|
      if s[:state] == :temp_taken || s[:state] == :temp_taken_used
        s[:state] = :normal
      elsif s[:state] == :temp_used || s[:state] == :taken_temp_used
        s[:state] = :taken
      end
      s[:obj] = s[:type].new(s[:x], s[:y], s[:args], s[:section], s) if s[:type]
    end
  end

  def save_switches
    @switches.each do |s|
      if s[:state] == :temp_taken
        s[:state] = :taken
      elsif s[:state] == :temp_used || s[:state] == :temp_taken_used || s[:state] == :taken_temp_used
        s[:state] = :used
      end
    end
    SB.player.lives += @life_count unless SB.casual?
    @life_count = 0
  end

  def switches_by_state(state)
    @switches.select{ |s| s[:state] == state }.map{ |s| s[:index] }
  end

  def add_switch(obj)
    @switches << {
      type: obj.class,
      obj: obj,
      x: 0,
      y: 0,
      section: @cur_section,
      state: :normal,
      index: @switches.size
    }
  end

  def delete_switch(obj)
    switch = find_switch(obj)
    @switches.delete(switch) unless switch.nil?
  end

  def stop_time(duration, all = true)
    @stopped = all ? :all : :enemies
    @stopped_timer = 0
    @stop_time_duration = duration
  end

  def resume_time
    @stopped = nil
  end

  def update_bomb
    @cur_section.update_passengers
  end

  def set_spec_taken
    @spec_taken = true
  end

  def get_startup_item
    w = SB.player.last_world
    possible_items = [
      Section::ELEMENT_TYPES.key(Attack1),
      Section::ELEMENT_TYPES.key(BoardItem),
      Section::ELEMENT_TYPES.key(Key),
      Section::ELEMENT_TYPES.key(Shield),
    ]
    possible_items += [
      Section::ELEMENT_TYPES.key(Attack2),
      Section::ELEMENT_TYPES.key(Spring),
    ] if w >= 2
    possible_items += [
      Section::ELEMENT_TYPES.key(Attack3),
    ] if w >= 3
    possible_items[rand(possible_items.size)]
  end

  def unlock_bomb?
    @world <= 3 && @num == SB.world.stage_count && @world == SB.player.last_world ||
      @world == 6 && @num == 1 && SB.player.last_stage == 1
  end

  def draw
    @cur_section.draw

    if @stopped == :all && @stopped_timer < 40
      alpha = @stopped_timer < 20 ? (@stopped_timer.to_f / 20 * 255).floor :
                                    (255 - (@stopped_timer - 20).to_f / 20 * 255).floor
      c = (alpha << 24) | 0xffffff
      G.window.draw_quad 0, 0, c,
                         C::SCREEN_WIDTH, 0, c,
                         0, C::SCREEN_HEIGHT, c,
                         C::SCREEN_WIDTH, C::SCREEN_HEIGHT, c, 0
    end

    if @starting == 1
      c = (@alpha << 24)
      G.window.draw_quad 0, 0, c,
                         C::SCREEN_WIDTH, 0, c,
                         0, C::SCREEN_HEIGHT, c,
                         C::SCREEN_WIDTH, C::SCREEN_HEIGHT, c, 0
      G.window.draw_quad @panel_x, 200, C::PANEL_COLOR,
                         @panel_x + 600, 200, C::PANEL_COLOR,
                         @panel_x, 400, C::PANEL_COLOR,
                         @panel_x + 600, 400, C::PANEL_COLOR, 0
      SB.text_helper.write_line @world_name, @panel_x + 300, 220, :center
      SB.text_helper.write_line(text: @name, x: @panel_x + 300, y: 300, mode: :center, scale_x: 3, scale_y: 3)
    elsif @starting == 2
      panel_color = ((@alpha / 2) << 24) | (C::PANEL_COLOR & 0xffffff)
      G.window.draw_quad 200, 10, panel_color,
                         600, 10, panel_color,
                         200, 70, panel_color,
                         600, 70, panel_color, 0
      SB.text_helper.write_line(text: @world_name, x: 400, y: 12, mode: :center, alpha: @alpha, scale_x: 1.5, scale_y: 1.5)
      SB.text_helper.write_line @name, 400, 35, :center, 0, @alpha
    elsif @warp_timer > 0
      alpha = (@warp_timer / 30.0 * 255).floor
      color = alpha << 24
      G.window.draw_quad(0, 0, color,
                         C::SCREEN_WIDTH, 0, color,
                         0, C::SCREEN_HEIGHT, color,
                         C::SCREEN_WIDTH, C::SCREEN_HEIGHT, color, 5)
    end
  end
end
