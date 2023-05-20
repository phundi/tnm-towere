class TowerController < ApplicationController

  def new_refill 
    @tower = Tower.find(params[:tower_id])
    @prev_refill = Refill.where(" tower_id = #{@tower.id} AND refill_type = '#{params[:type]}'  ")
                    .order(" refill_date ASC, created_at ASC ").last
    @refill = Refill.new 
    @unit = params[:type].upcase == "ESCOM" ? "Units" : "Litres"

    if request.post?

      @refill.refill_date = params[:refill_date] #Time.now 
      @refill.reading_before_refill  = params[:reading_before_refill]
      @refill.reading_after_refill  = params[:refill_final_reading]
      @refill.refill_amount  = params[:refill_amount]
      @refill.usage = params[:refill_usage]
      @refill.genset_reading = params[:genset_reading]
      @refill.genset_run_time = params[:refill_run_hours]
      @refill.refill_type  = params[:type].upcase
      @refill.tower_id  = @tower.id 
      @refill.creator = @cur_user.id
      @refill.save!

      redirect_to "/tower/view?tower_id=#{@tower.id}"
    end 

  end 

  def tower_types
    @tower_types = TowerType.where(voided: 0).order('name')
  end

  def index
    @types = TowerType.where(voided: 0)
    @label = Date.today.strftime("%b, %Y")
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

    escom_refills_count = Refill.where(" tower_id = #{@tower.id} AND refill_type = 'ESCOM'  ").count
    fuel_refills_count = Refill.where(" tower_id = #{@tower.id} AND refill_type = 'FUEL'  ").count

    @modules = []
    @modules <<  ['ESCOM Units Refills', escom_refills_count, "/tower/refills?type=escom&tower_id=#{@tower.id}" ]
    @modules <<  ['Fuel Refills', fuel_refills_count, "/tower/refills?type=fuel&tower_id=#{@tower.id}"]

    @common_encounters = []
    @common_encounters << ['New Escom Units Refill', '/tower/new_refill?type=ESCOM']
    @common_encounters << ['New Fuel Refill', '/tower/new_refill?type=FUEL']
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


    if params[:start_date].present? and params[:end_date].present?
      start_date =  params[:start_date].to_date.to_s(:db) 
      end_date =  params[:end_date].to_date.to_s(:db) 
    else
      start_date = Date.today.beginning_of_month.to_s(:db)
      end_date = Date.today.end_of_month.to_s(:db)
    end 
    mtd_date_filter = " AND refill_date BETWEEN '#{start_date}' AND '#{end_date}' "

    search_val = params[:search][:value] rescue nil
    search_val = '' if search_val.blank?

    tag_filter = ''
    flagged_filter = ''
    having_filter = ''
    search_filter = ''

    if params[:type_id].present?
      tag_filter = " AND tower.tower_type_id = #{params[:type_id]}"
    end

    if params[:flagged].present? and params[:flagged].to_s == "true"

      having_filter = " AND (usage_mtd/run_hours_mtd) > 3 "
      
    end

    if search_val.present?
      search_filter = " AND tower.name REGEXP '#{search_filter}' "
    end 

    data = Tower.order(' tower.created_at DESC ')
    data = data.where(" #{search_filter}
         #{tag_filter} ")
    total = data.select(" count(*) c ")[0]['c'] rescue 0
    page = (params[:start].to_i / params[:length].to_i) + 1


    data = data.select(" tower.* , 
    
    (SELECT SUM(refill.usage) FROM refill 
            WHERE refill.tower_id = tower.tower_id AND refill_type = 'FUEL' #{mtd_date_filter}) AS usage_mtd,

            (SELECT SUM(refill.genset_run_time) FROM refill 
                    WHERE refill.tower_id = tower.tower_id AND refill_type = 'FUEL' #{mtd_date_filter}) AS run_hours_mtd

     ").having(" true #{having_filter} ")

    data = data.page(page).per_page(params[:length].to_i)
    

    @records = []
    data.each do |p|
      type = TowerType.find(p.tower_type_id).name rescue nil
      
      escom_refill = Refill.where(" tower_id = #{p.id} AND refill_type = 'ESCOM'  ")
      .order(" refill_date").last

      fuel_refill = Refill.where(" tower_id = #{p.id} AND refill_type = 'FUEL'  ")
      .order(" refill_date ").last


      fuel_refill_last_month = Refill.where(" tower_id = #{p.id} AND refill_type = 'FUEL'  
        AND refill_date < '#{start_date}'
      ").order(" refill_date ").last 

      escom_refill_last_month = Refill.where(" tower_id = #{p.id} AND refill_type = 'ESCOM'  
        AND refill_date < '#{start_date}'
      ").order(" refill_date ").last  

      escom_refills_mtd = Refill.find_by_sql(" SELECT SUM(refill_amount) AS total FROM refill 
                    WHERE tower_id = #{p.id} AND refill_type = 'ESCOM' 
                     " ).last.total rescue 0

      fuel_refills_mtd = Refill.find_by_sql(" SELECT SUM(refill_amount) AS total FROM refill 
                    WHERE tower_id = #{p.id} AND refill_type = 'FUEL' #{mtd_date_filter} " ).last.total rescue 0

      escom_usage_mtd = Refill.find_by_sql(" SELECT SUM(refill.usage) AS total FROM refill 
                    WHERE tower_id = #{p.id} AND refill_type = 'ESCOM' #{mtd_date_filter} " ).last.total rescue 0

      rate = (p.usage_mtd.to_f/p.run_hours_mtd.to_f).round(2)


      rdate = [(fuel_refill.refill_date rescue nil), (escom_refill.refill_date rescue nil)].delete_if{|s| 
                s.blank?}.max.strftime("%Y-%m-%d %H:%M") rescue ""
      
      if rate > 3
          rate = "<span style='color:red'>#{rate}</span>"
      end 

      row = [rdate,
                p.name, 
                (fuel_refill_last_month.reading_after_refill rescue ""),
                fuel_refills_mtd,
                (fuel_refill.reading_after_refill rescue ""),
                p.usage_mtd,
                (fuel_refill_last_month.genset_reading rescue ""),
                (fuel_refill.genset_reading rescue ""),
                p.run_hours_mtd,
                rate,
                (escom_refill_last_month.reading_after_refill rescue ""),
                escom_refills_mtd,
                (escom_refill.reading_after_refill rescue ""),
                escom_usage_mtd,
                p.id]
      @records << row
    end

    render :text => {
        "draw" => params[:draw].to_i,
        "recordsTotal" => total,
        "recordsFiltered" => total,
        "data" => @records}.to_json and return
  end

  def refills

    start_date, end_date = date_ranges
    tower_id = params[:tower_id]
    tower_filter = " "; tower_name = ""
    if tower_id.present?
      tower_name = " for " + Tower.find(tower_id).name 
      tower_filter = " AND t.tower_id = #{tower_id}"
    end 

    type_filter = " "

    @title = "Listing of #{params[:type]} Refills #{tower_name}"

    @data = [
                ["Refill date", "Tower", "District", "Technician", "Refill type", 
              "Reading before refill", "Usage"]]

    if params[:type] != 'escom'
      @data[0] << "Run hrs"
      @data[0] << "Rate (Litres/hr)"

    end

    @data[0] = @data[0] + ["Refill amount", "Final reading"]
    
    if params[:type] == "escom"
      type_filter = " AND r.refill_type = 'ESCOM' "
    elsif params[:type] == "fuel"
      type_filter = " AND r.refill_type = 'FUEL' "
    end 

    data = Tower.find_by_sql("
          SELECT r.*, l.code, t.name FROM refill r  
            INNER JOIN tower t ON t.tower_id = r.tower_id
            INNER JOIN location l ON l.location_id = t.district_id
            WHERE DATE(r.refill_date) BETWEEN '#{start_date}' AND '#{end_date}'
            #{tower_filter} #{type_filter} ORDER BY refill_date DESC
    ").each do |t|
        
        creator = User.find(t.creator).name   
        
        rate = ""
        if t.usage.present? and t.usage > 0 and t.genset_run_time.present? and t.genset_run_time > 0
          rate = (t.usage/t.genset_run_time.to_f).round(2)
          if rate > 3
            rate = "<span style='color:red'>#{rate}</span>".html_safe
          end 
        end 
        
        row = [   
          t.refill_date.strftime("%Y-%m-%d %H:%M"),
          t.name, 
                t.code, 
                creator,
                t.refill_type,
                t.reading_before_refill,
                t.usage
              ]

              if params[:type] != 'escom'
                row << t.genset_run_time
                row << rate
              end 

              row += [
                t.refill_amount,
                t.reading_after_refill,
                t.id
          ]
      @data << row
    end


    render template: "tower/generic_table"  
end



  def date_ranges 
      
    start_date, end_date = ["1900-01-01".to_date.to_s, Date.today.to_s]
    start_date = params[:start_date].to_date.to_s if params[:start_date].present?
    end_date = params[:end_date].to_date.to_s if params[:end_date].present?

    if params['period'].present?
      start_date, end_date = {
        "today" => [Date.today, Date.today],
        "week"  => [Time.now.beginning_of_week.to_date, Time.now.end_of_week.to_date],
        "month"  => [Time.now.beginning_of_month.to_date, Time.now.end_of_month.to_date],
        "year"  => [Time.now.beginning_of_year.to_date, Time.now.end_of_year.to_date],
        "eversince"  => ["1900-01-01".to_date.to_s, Date.today.to_s]
      }[params['period']]
    end 

    [start_date, end_date]
  end

end 