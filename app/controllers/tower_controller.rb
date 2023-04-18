class TowerController < ApplicationController
  def tower_types
    @tower_types = TowerType.where(voided: 0).order('name')
  end

  def index
    @types = TowerType.where(voided: 0)
  end

  def new
    @tower = Tower.new
    @action = "/tower/new"
    @types = TowerType.where(voided: 0)

    district_tag = LocationTag.where(name: "District").first 
    @districts = Location.find_by_sql("select * from location l INNER JOIN location_tag_map tm ON tm.location_id = l.location_id 
      WHERE tm.location_tag_id = #{district_tag.id}")


    if request.post?
      @tower = Tower.new
      @tower.tower_type_id = params[:type]
      @tower.name = params[:name]
      @tower.district_id = params[:district]
      @tower.lat = params[:lat]
      @tower.long = params[:long]
      @tower.description = params[:description].strip
      @tower.creator = @cur_user.id
      @tower.save
      redirect_to "/tower/view?tower_id=#{@tower.id}"
    end
  end

  def edit
    @tower = Tower.find(params[:tower_id])

    district_tag = LocationTag.where(name: "District").first 
    @districts = Location.find_by_sql("select * from location l INNER JOIN location_tag_map tm ON tm.location_id = l.location_id 
      WHERE tm.location_tag_id = #{district_tag.id}")

    @action = "/tower/edit"
    @types = TowerType.where(voided: 0)

    if request.post?
      @tower.tower_type_id = params[:type]
      @tower.name = params[:name]
      @tower.district_id = params[:district]
      @tower.lat = params[:lat]
      @tower.long = params[:long]
      @tower.description = params[:description].strip
      @tower.creator = @cur_user.id
      @tower.save
      redirect_to "/tower/view?tower_id=#{@tower.id}"
    end
  end

  def view
    @tower = Tower.find(params[:tower_id])
    @tower_type = TowerType.find(@tower.tower_type_id).name
    @district_name = Location.find(@tower.district_id).name
    @creator = User.find(@tower.creator).name

    @modules = []
    @modules <<  ['Fuel Refills', 0, "/tower/refills?tower_id=#{@tower.id}"]
    @modules <<  ['ESCOM Units Refills', 0, "/tower/refills?tower_id=#{@tower.id}" ]

    @common_encounters = []
    @common_encounters << ['New Escom Units Refill', '/tower/escom_refill']
    @common_encounters << ['New Fuel Refill', '/tower/full_refill']
  end

  def new_type
    @tower_type = TowerType.new
    @action = "/tower/new_type"
    if request.post?
      TowerType.create(name: params[:name], description: params[:description], voided: 0)
      redirect_to "/tower/tower_types" and return
    end
  end

  def view_type
    @tower_type = TowerType.find(params[:type_id])
  end

  def edit_type
    @action = "/tower/edit_type"
    @tower_type = TowerType.find(params[:type_id])
    if request.post?
      @tower_type.name = params[:name]
      @tower_type.description = params[:description]
      @tower_type.save
      redirect_to "/tower/tower_types" and return
    end
  end

  def delete_type
    type = TowerType.find(params[:type_id])
    type.voided = 1
    type.save
    redirect_to '/tower/tower_types'
  end

  def ajax_towers

    search_val = params[:search][:value] rescue nil
    search_val = '_' if search_val.blank?

    tag_filter = ''
    code_filter = ''

    if (params[:search][:value] rescue nil).present?
      search_code = search_val.soundex rescue '_'
      code_filter = " OR first_name_code = '#{search_code}' OR last_name_code = '#{search_code}'"
    end

    if params[:type_id].present?
      tag_filter = " AND tower.tower_type_id = #{params[:type_id]}"
    end

    data = tower.order(' tower.created_at DESC ')
    data = data.where(" ((CONCAT_WS(first_name, middle_name, last_name, gender, birthdate, address, email, occupation, phone_number, '_') REGEXP '#{search_val}')
         #{tag_filter}) #{code_filter}")
    total = data.select(" count(*) c ")[0]['c'] rescue 0
    page = (params[:start].to_i / params[:length].to_i) + 1

    data = data.select(" tower.* ")
    data = data.page(page).per_page(params[:length].to_i)

    @records = []
    data.each do |p|
      gender = p.gender.to_i == 1 ? "M" : 'F'
      type = TowerType.find(p.tower_type_id).name rescue nil
      name = "#{p.first_name} #{p.middle_name} #{p.last_name}(#{gender})".gsub(/\s+/, ' ')
      dob = p.birthdate.to_date.strftime("%d-%b-%Y") rescue nil
      row = [name, p.identifier, dob, type, p.phone_number, p.address, p.id]
      @records << row
    end

    render :text => {
        "draw" => params[:draw].to_i,
        "recordsTotal" => total,
        "recordsFiltered" => total,
        "data" => @records}.to_json and return
  end

  def tower_suggestions
    query = " "
    (params[:search_params] || []).each do |k, v|
      next if v.blank?

      if k == 'first_name'
        k = 'first_name_code'
        v = v.soundex
      end

      if k == 'last_name'
        k = 'last_name_code'
        v = v.soundex
      end

      if k == 'birthdate'
        v = v.to_date.strftime('%Y-%m-%d')
      end

      if k == 'gender'

      end

      query += " AND #{k} RLIKE '#{v}' "
    end

    results = []
    if query.strip.length > 0
      results = tower.where(" created_at IS NOT NULL #{query}").limit(20);
    end

    response = []
    (results || []).each do |result|
      gender = result.gender.to_i == 1 ? "M" : 'F'
      response << {
          'dob' => result.birthdate.to_date.strftime("%d-%b-%Y"),
          'occupation' => result.occupation,
          'name' => "#{result.first_name} #{(result.middle_name.split('')[0] rescue '')} #{result.last_name} (#{gender})".gsub(/\s+/, ' '),
          'address' => result.address,
          'phone_number' => result.phone_number,
          'tower_id' => result.id
      }
    end

    render text: response.to_json
  end
end