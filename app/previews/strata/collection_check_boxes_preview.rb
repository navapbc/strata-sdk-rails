# frozen_string_literal: true

module Strata
  # CollectionCheckBoxesPreview provides preview examples for the collection_check_boxes component.
  # It demonstrates different states of checkbox collections including empty selection,
  # selected items, and invalid states.
  #
  # This class is used with Lookbook to generate UI component previews
  # for the collection_check_boxes form component.
  #
  # @example Viewing the selected state preview
  #   # In Lookbook UI
  #   # Navigate to Strata > CollectionCheckBoxesPreview > selected
  #
  class CollectionCheckBoxesPreview < Lookbook::Preview
    layout "strata/component_preview"

    # Simple struct to represent a service option
    Service = Struct.new(:id, :name)

    # @label Empty
    # Shows an empty collection with no items selected
    def empty
      model = TestRecord.new
      services = build_services
      render template: "strata/previews/_collection_check_boxes",
             locals: { model: model, services: services, legend_options: {} }
    end

    # @label Selected
    # Shows a collection with some items pre-selected
    def selected
      model = TestRecord.new
      model.service_ids = [1, 3]
      services = build_services
      render template: "strata/previews/_collection_check_boxes",
             locals: { model: model, services: services, legend_options: {} }
    end

    # @label Invalid
    # Shows a collection with validation errors
    def invalid
      model = TestRecord.new
      model.errors.add(:service_ids, "must select at least one service")
      services = build_services
      render template: "strata/previews/_collection_check_boxes",
             locals: { model: model, services: services, legend_options: {} }
    end

    # @label Custom Legend
    # Shows a collection with a custom legend
    def custom_legend
      model = TestRecord.new
      services = build_services
      render template: "strata/previews/_collection_check_boxes",
             locals: { model: model, services: services, legend_options: { legend: "Which additional services would you like?" } }
    end

    # @label Without Tile Style
    # Shows a collection without the tile style
    def without_tile
      model = TestRecord.new
      services = build_services
      render template: "strata/previews/_collection_check_boxes",
             locals: { model: model, services: services, legend_options: { tile: false } }
    end

    private

    def build_services
      [
        Service.new(1, "Expedited Processing"),
        Service.new(2, "Additional Pages"),
        Service.new(3, "Certified Copies")
      ]
    end
  end
end
