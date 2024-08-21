class Allocation < ApplicationRecord
  belongs_to :fund
  has_many :project_allocations

  def calculate_funded_projects
    # get a list of all possible projects for this fund

    # calculate scores for each project

    # sort projects by score

    # allocate funds to the top projects

    # save the project allocations
  end
end
