module Api
  module V1
    # Finding something to log.
    #
    # `index` is the catalog this user can already log from — the shared rows
    # plus their own. `search` is the outside world: Open Food Facts, one
    # outbound request per call, which is why it carries its own throttle.
    # `create` is how a search result becomes something loggable, because a
    # logged entry points at a `Food` row rather than carrying a name.
    class FoodsController < BaseController
      MAX_LIMIT = 100
      DEFAULT_LIMIT = 50

      def index
        foods = Food.available_to(current_user)
        foods = matching(foods) if params[:q].present?
        total = foods.count
        page = foods.limit(limit).offset(offset)

        render json: {
          data: page.map { |food| FoodSerializer.new(food).as_json },
          meta: {
            returned: page.length,
            total: total,
            limit: limit,
            offset: offset,
            next_offset: (offset + limit < total ? offset + limit : nil)
          }
        }
      end

      # Not `Food` rows — these are results from somewhere else, and nothing is
      # written until the client posts one back to `create`. A network failure
      # degrades to an empty list rather than an error, because the catalog and
      # the user's own foods are still there to log from.
      def search
        results = FoodDatabaseSearch.new(params[:q].to_s).call

        render json: { data: results.map { |result| result_json(result) } }
      end

      def create
        attributes = food_params
        name = attributes[:name].to_s.strip
        brand = attributes[:brand].presence
        existing = current_user.foods.find_by(name: name, brand: brand)

        # Adding the same food twice is what a flaky phone connection looks
        # like, so it finds the one already there rather than filling the
        # catalog with duplicates.
        return render(json: { data: FoodSerializer.new(existing).as_json }) if existing

        food = current_user.foods.new(attributes.merge(name: name, brand: brand, source: source_for(attributes)))

        if food.save
          render json: { data: FoodSerializer.new(food).as_json }, status: :created
        else
          render json: { error: "Invalid food", details: food.errors.full_messages },
            status: :unprocessable_entity
        end
      end

      private

      def matching(foods)
        query = ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)
        foods.where("foods.name ILIKE :q OR foods.brand ILIKE :q", q: "%#{query}%")
      end

      def limit
        params.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
      end

      def offset
        [ params.fetch(:offset, 0).to_i, 0 ].max
      end

      def food_params
        params.require(:food).permit(
          :name, :brand, :barcode, :serving_grams, :kcal, :protein_g, :carb_g, :fat_g
        )
      end

      # Where the numbers came from, which is worth recording: a food scanned
      # off a packet and one typed in by hand are trusted differently, and only
      # the client knows which happened.
      def source_for(attributes)
        attributes[:barcode].present? ? "barcode" : "manual"
      end

      def result_json(result)
        {
          name: result.name,
          brand: result.brand,
          barcode: result.code,
          serving_grams: result.serving_grams.to_f,
          kcal: result.kcal.to_f,
          protein_g: result.protein_g.to_f,
          carb_g: result.carb_g.to_f,
          fat_g: result.fat_g.to_f
        }
      end
    end
  end
end
