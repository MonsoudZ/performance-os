# A record whose children carry a user-visible order.
#
# A meal's foods and a workout's exercises answer the same question — what order
# do these read in — and the editor screen is literally the same Stimulus
# controller, with the same move-up and move-down buttons writing a hidden
# `position` on each row. The rule for turning those into stored positions lived
# in two controllers instead of one, and they drifted: the workout's copy sorted
# by the position the form submitted, the meal's copy ignored it and numbered by
# whatever order the association happened to be loaded in. Since a persisted
# record loads its children in their *old* position order and nested attributes
# update them in place, that meant every reorder on the meal editor was silently
# thrown away on save.
#
# So it is declared once, here, and both call it.
module OrderedItems
  extend ActiveSupport::Concern

  class_methods do
    # Names the association whose `position` column is the order the user sees.
    def ordered_by_position(association)
      define_method(:renumber_items) do
        public_send(association)
          .reject(&:marked_for_destruction?)
          # `with_index` keeps the sort stable, so rows arriving without a
          # position — a row the user has just added — land at the end in the
          # order they were added rather than in whatever order Ruby likes.
          .sort_by.with_index { |item, index| [ item.position || Float::INFINITY, index ] }
          .each_with_index { |item, index| item.position = index + 1 }
      end
    end
  end
end
