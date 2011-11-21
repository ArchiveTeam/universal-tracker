Feature: Work items
	In order to coordinate work amongst downloaders
	Downloaders must be able to check out names of users.

	Scenario: Requesting a work item
		Given the tracker has the work items
			| item   |
			| abc123 |
			| def456 |

		When I request a work item as "foobar"

		Then the response has status 200
		Then I receive a work item

	Scenario: When no work items are unclaimed
		When I request a work item as "foobar"

		Then the response has status 404
