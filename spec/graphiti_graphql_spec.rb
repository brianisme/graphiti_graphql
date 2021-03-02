require "spec_helper"

RSpec.describe GraphitiGraphQL do
  describe "basic" do
    include_context "resource testing"
    let(:resource) do
      Class.new(PORO::EmployeeResource) do
        def self.name
          "PORO::EmployeeResource"
        end
      end
    end

    let!(:employee1) do
      PORO::Employee.create(first_name: "Stephen", last_name: "King", age: 60)
    end
    let!(:employee2) do
      PORO::Employee.create(first_name: "Agatha", last_name: "Christie", age: 70)
    end

    describe "fetching single entity" do
      context "via hardcoding" do
        it "works" do
          json = run(%|
            query getEmployee {
              employee(id: "2") {
                firstName
              }
            }
          |)
          expect(json).to eq({
            employee: {
              firstName: "Agatha"
            }
          })
        end
      end

      context "via variables" do
        it "works" do
          json = run(%|
            query getEmployee($id: String!) {
              employee(id: $id) {
                firstName
              }
            }
          |, {"id" => "2"})
          expect(json).to eq({
            employee: {
              firstName: "Agatha"
            }
          })
        end
      end

      it "can be null" do
        json = run(%|
          query getEmployee {
            employee(id: "999") {
              firstName
            }
          }
        |)
        expect(json).to eq({
          employee: nil
        })
      end

      it "does not support filtering" do
        json = run(%|
          query getEmployee {
            employee(id: "2", filterFirstNameEq: "Agatha") {
              firstName
            }
          }
        |)
        expect(json[:errors][0][:message])
          .to eq("Field 'employee' doesn't accept argument 'filterFirstNameEq'")
      end

      it "does not support sorting" do
        json = run(%|
          query getEmployee {
            employee(id: "2", sort: [{ att: firstName, dir: desc }]) {
              firstName
            }
          }
        |)
        expect(json[:errors][0][:message])
          .to eq("Field 'employee' doesn't accept argument 'sort'")
      end

      it "does not support pagination" do
        json = run(%|
          query getEmployee {
            employee(id: "2", page: { size: 1, number: 2 }) {
              firstName
            }
          }
        |)
        expect(json[:errors][0][:message])
          .to eq("Field 'employee' doesn't accept argument 'page'")
      end

      context "when the graphql_entrypoint is customized" do
        before do
          resource.graphql_entrypoint = :exemplaryEmployees
          schema!
        end

        it "works" do
          json = run(%(
            query {
              exemplaryEmployee(id: "1") {
                firstName
              }
            }
          ))
          expect(json[:exemplaryEmployee]).to eq({
            firstName: "Stephen"
          })
        end

        it "does not expose the jsonapi type as an entrypoint" do
          json = run(%(
            query {
              employee(id: "1") {
                firstName
              }
            }
          ))
          expect(json[:errors][0][:message])
            .to eq("Field 'employee' doesn't exist on type 'Query'")
        end
      end
    end

    describe "when the graphql entrypoint is customized" do
      before do
        resource.graphql_entrypoint = :exemplaryEmployees
        schema!
      end

      it "works" do
        json = run(%(
          query {
            exemplaryEmployees {
              firstName
            }
          }
        ))
        expect(json).to eq({
          exemplaryEmployees: [
            {firstName: "Stephen"},
            {firstName: "Agatha"}
          ]
        })
      end

      it "does not expose the jsonapi type" do
        json = run(%(
          query {
            employees {
              firstName
            }
          }
        ))
        expect(json[:errors][0][:message])
          .to eq("Field 'employees' doesn't exist on type 'Query'")
      end

      context "on a relationship" do
        before do
          PORO::Position.create(title: "postitle", employee_id: employee1.id)
          resource.graphql_entrypoint = :employees
          position_resource = Class.new(PORO::PositionResource) {
            def self.name
              "PORO::PositionResource"
            end
            self.graphql_entrypoint = :empPositions
          }
          resource.has_many :positions, resource: position_resource
          schema!
        end

        it "is still queried via relationship name" do
          json = run(%(
            query {
              employees {
                positions {
                  title
                }
              }
            }
          ))
          expect(json).to eq({
            employees: [
              {positions: [{title: "postitle"}]},
              {positions: []}
            ]
          })
        end
      end
    end

    describe "fields" do
      describe "basic" do
        it "works, does not render id automatically, camelizes keys" do
          json = run(%(
            query getEmployees {
              employees {
                firstName
                lastName
              }
            }
          ))
          expect(json).to eq({
            employees: [
              {
                firstName: "Stephen",
                lastName: "King"
              },
              {
                firstName: "Agatha",
                lastName: "Christie"
              }
            ]
          })
        end

        it "can render every type" do
          now = Time.now
          allow(Time).to receive(:now) { now }
          json = run(%(
            query getEmployees {
              employees {
                id
                firstName
                active
                age
                change
                createdAt
                today
                objekt
                stringies
                ints
                floats
                datetimes
                scalarArray
                objectArray
              }
            }
          ))
          expect(json).to eq({
            employees: [
              {
                active: true,
                age: 60,
                change: 0.76,
                createdAt: now.iso8601,
                today: now.to_date,
                firstName: "Stephen",
                id: "1",
                objekt: {foo: "bar"},
                stringies: ["foo", "bar"],
                ints: [1, 2],
                floats: [0.01, 0.02],
                datetimes: [now.iso8601, now.iso8601],
                scalarArray: [1, 2],
                objectArray: [{foo: "bar"}, {baz: "bazoo"}]
              },
              {
                active: true,
                age: 70,
                change: 0.76,
                createdAt: now.iso8601,
                today: now.to_date,
                firstName: "Agatha",
                id: "2",
                objekt: {foo: "bar"},
                stringies: ["foo", "bar"],
                ints: [1, 2],
                floats: [0.01, 0.02],
                datetimes: [now.iso8601, now.iso8601],
                scalarArray: [1, 2],
                objectArray: [{foo: "bar"}, {baz: "bazoo"}]
              }
            ]
          })
        end

        context "when a custom type" do
          before do
            type = Dry::Types::Nominal
              .new(nil)
              .constructor { |input|
                "custom!"
              }
            Graphiti::Types[:custom] = {
              read: type,
              write: type,
              params: type,
              kind: "scalar",
              description: "test",
              canonical_name: :string
            }
            resource.attribute :my_custom, :custom do
              "asdf"
            end
            schema!
          end

          after do
            Graphiti::Types.map.delete(:custom)
          end

          it "also works, via canonical_name" do
            json = run(%(
              query {
                employees {
                  myCustom
                }
              }
            ))
            expect(json).to eq({
              employees: [
                {myCustom: "custom!"},
                {myCustom: "custom!"}
              ]
            })
          end
        end

        context "attribute objects with a defined schema" do
          xit "applies the schema for GraphQL" do
          end
        end
      end

      context "when id and _type are requested" do
        it "works" do
          json = run(%(
            query getEmployees {
              employees {
                id
                _type
                firstName
              }
            }
          ))
          expect(json).to eq({
            employees: [
              {
                id: employee1.id.to_s,
                _type: "employees",
                firstName: "Stephen"
              },
              {
                id: employee2.id.to_s,
                _type: "employees",
                firstName: "Agatha"
              }
            ]
          })
        end
      end

      context "when guarded field is requested" do
        before do
          resource.class_eval do
            attribute :foo, :string, readable: :admin? do
              "bar!"
            end

            def admin?
              context.current_user == "admin"
            end
          end
          schema!
        end

        around do |e|
          ctx = OpenStruct.new(current_user: current_user)
          Graphiti.with_context ctx do
            e.run
          end
        end

        context "and the guard passes" do
          let(:current_user) { "admin" }

          it "works" do
            json = run(%(
              query {
                employees {
                  foo
                }
              }
            ))
            expect(json).to eq({
              employees: [
                {foo: "bar!"},
                {foo: "bar!"}
              ]
            })
          end
        end

        context "and the guard fails" do
          let(:current_user) { "not admin" }

          it "returns error" do
            expect {
              run(%(
                query {
                  employees {
                    foo
                  }
                }
              ))
            }.to raise_error(Graphiti::Errors::UnreadableAttribute, /foo/)
          end
        end
      end

      context "when extra_field is requested" do
        it "is still works" do
          json = run(%(
            query getEmployees {
              employees {
                worth
              }
            }
          ))
          expect(json).to eq({
            employees: [
              {worth: 100},
              {worth: 100}
            ]
          })
        end
      end

      context "when a field is not readable" do
        before do
          resource.class_eval do
            attribute :foo, :string, only: [:writable]
          end
          schema!
        end

        it "returns error" do
          json = run(%(
            query getEmployees {
              employees {
                firstName
                foo
              }
            }
          ))
          expect(json).to eq({
            errors: [
              {
                extensions: {
                  code: "undefinedField",
                  fieldName: "foo",
                  typeName: "POROEmployee"
                },
                locations: [
                  {
                    column: 17,
                    line: 5
                  }
                ],
                message: "Field 'foo' doesn't exist on type 'POROEmployee'",
                path: ["query getEmployees", "employees", "foo"]
              }
            ]
          })
        end
      end

      context "when a field is customized" do
        before do
          resource.attribute :foo, :string do
            @object.first_name.upcase
          end
          schema!
        end

        it "is reflected in the result" do
          json = run(%(
            query getEmployees {
              employees {
                foo
              }
            }
          ))
          expect(json).to eq({
            employees: [
              {
                foo: "STEPHEN"
              },
              {
                foo: "AGATHA"
              }
            ]
          })
        end
      end

      context "when relationship fields" do
        let!(:position1) do
          PORO::Position.create title: "Manager",
                                employee_id: employee1.id,
                                department_id: department.id
        end

        let!(:department) do
          PORO::Department.create(name: "Security")
        end

        it "respects the request" do
          json = run(%(
            query getEmployees {
              employees {
                firstName
                positions {
                  id
                  title
                  department {
                    _type
                    name
                  }
                }
              }
            }
          ))
          expect(json).to eq({
            employees: [
              {
                firstName: "Stephen",
                positions: [{
                  id: position1.id.to_s,
                  title: "Manager",
                  department: {
                    _type: "departments",
                    name: "Security"
                  }
                }]
              },
              {
                firstName: "Agatha",
                positions: []
              }
            ]
          })
        end

        context "when the relationship should be camelized" do
          before do
            resource.has_many :foo_positions, resource: PORO::PositionResource
            schema!
          end

          it "is" do
            json = run(%(
              query getEmployees {
                employees {
                  fooPositions {
                    title
                  }
                }
              }
            ))
            expect(json).to eq({
              employees: [
                {
                  fooPositions: [{title: "Manager"}]
                },
                {
                  fooPositions: []
                }
              ]
            })
          end
        end

        context "that are marked unreadable" do
          before do
            position_resource = Class.new(PORO::PositionResource) {
              def self.name
                "PORO::PositionResource"
              end
              attribute :title, :string, readable: false
            }
            resource.has_many :positions, resource: position_resource
            schema!
          end

          it "returns error" do
            json = run(%(
              query getEmployees {
                employees {
                  firstName
                  positions {
                    id
                    title
                  }
                }
              }
            ))
            expect(json).to eq({
              errors: [
                extensions: {
                  code: "undefinedField",
                  fieldName: "title",
                  typeName: "POROPosition"
                },
                locations: [{
                  column: 21,
                  line: 7
                }],
                message: "Field 'title' doesn't exist on type 'POROPosition'",
                path: ["query getEmployees", "employees", "positions", "title"]
              ]
            })
          end
        end
      end
    end

    describe "filtering" do
      context "via hardcoded request" do
        it "works" do
          json = run(%|
            query getEmployees {
              employees(filter: { firstName: { eq: "Agatha" } }) {
                id
                firstName
              }
            }
          |)
          expect(json[:employees]).to eq([{
            id: employee2.id.to_s,
            firstName: "Agatha"
          }])
        end
      end

      context "via variables" do
        it "works" do
          json = run(%|
            query getEmployees($name: String) {
              employees(filter: { firstName: { eq: $name } }) {
                id
                firstName
              }
            }
          |, {"name" => "Agatha"})
          expect(json[:employees]).to eq([{
            id: employee2.id.to_s,
            firstName: "Agatha"
          }])
        end
      end

      context "when not filterable" do
        before do
          resource.class_eval do
            attribute :first_name, :string, filterable: false
          end
          schema!
        end

        it "returns error" do
          json = run(%|
            query getEmployees($name: String) {
              employees(filter: { firstName: { eq: $name } }) {
                id
                firstName
              }
            }
          |, {"name" => "Agatha"})
          expect(json).to eq({
            errors: [
              {
                extensions: {
                  argumentName: "firstName",
                  code: "argumentNotAccepted",
                  name: "POROEmployeeFilter",
                  typeName: "InputObject"
                },
                locations: [{
                  column: 35,
                  line: 3
                }],
                message: "InputObject 'POROEmployeeFilter' doesn't accept argument 'firstName'",
                path: ["query getEmployees", "employees", "filter", "firstName"]
              },
              {
                extensions: {
                  code: "variableNotUsed",
                  variableName: "name"
                },
                locations: [{
                  column: 13,
                  line: 2
                }],
                message: "Variable $name is declared by getEmployees but not used",
                path: ["query getEmployees"]
              }
            ]
          })
        end
      end

      context "when operator not supported" do
        before do
          resource.class_eval do
            filter :first_name, only: [:prefix]
          end
          schema!
        end

        it "returns error" do
          json = run(%|
            query getEmployees($name: String) {
              employees(filter: { firstName: { eq: "A" } }) {
                id
                firstName
              }
            }
          |)
          expect(json).to eq({
            errors: [
              {
                extensions: {
                  argumentName: "eq",
                  code: "argumentNotAccepted",
                  name: "POROEmployeeFilterFilterfirstName",
                  typeName: "InputObject"
                },
                locations: [{
                  column: 48,
                  line: 3
                }],
                message: "InputObject 'POROEmployeeFilterFilterfirstName' doesn't accept argument 'eq'",
                path: ["query getEmployees", "employees", "filter", "firstName", "eq"]
              },
              {
                extensions: {
                  code: "variableNotUsed",
                  variableName: "name"
                },
                locations: [{
                  column: 13,
                  line: 2
                }],
                message: "Variable $name is declared by getEmployees but not used",
                path: ["query getEmployees"]
              }
            ]
          })
        end
      end

      context "when filter is guarded" do
        context "and guard does not pass" do
          it "returns error" do
            running = lambda do
              run(%|
                query getEmployees {
                  employees(filter: { guardedFirstName: { eq: "Agatha" } }) {
                    id
                    firstName
                  }
                }
              |)
            end
            expect(running).to raise_error(Graphiti::Errors::InvalidAttributeAccess, /guarded_first_name/)
          end
        end

        context "and guard passes" do
          it "works as normal" do
            ctx = OpenStruct.new(current_user: "admin")
            Graphiti.with_context(ctx, :index) do
              json = run(%|
                query getEmployees {
                  employees(filter: { guardedFirstName: { eq: "Agatha" } }) {
                    firstName
                  }
                }
              |)
              expect(json).to eq({
                employees: [{
                  firstName: "Agatha"
                }]
              })
            end
          end
        end
      end

      context "when on a relationship" do
        let!(:wrong_employee) do
          PORO::Position.create title: "Wrong",
                                employee_id: employee1.id,
                                active: true
        end

        let!(:position2) do
          PORO::Position.create title: "Manager",
                                employee_id: employee2.id
        end

        let!(:active) do
          PORO::Position.create title: "Engineer",
                                employee_id: employee2.id,
                                active: true
        end

        let!(:inactive) do
          PORO::Position.create title: "Old Manager",
                                employee_id: employee2.id,
                                active: false
        end

        context "via hardcoded request" do
          it "works" do
            json = run(%|
              query getEmployees {
                employees(filter: { firstName: { eq: "Agatha" } }) {
                  id
                  firstName
                  positions(filter: { active: { eq: true } }) {
                    title
                  }
                }
              }
            |)
            expect(json[:employees]).to eq([{
              id: employee2.id.to_s,
              firstName: "Agatha",
              positions: [{
                title: "Engineer"
              }]
            }])
          end
        end

        context "via variables" do
          it "works" do
            json = run(%|
              query getEmployees($name: String, $active: Boolean) {
                employees(filter: { firstName: { eq: $name } }) {
                  id
                  firstName
                  positions(filter: { active: { eq: $active } }) {
                    title
                  }
                }
              }
            |, {"name" => "Agatha", "active" => true})
            expect(json[:employees]).to eq([{
              id: employee2.id.to_s,
              firstName: "Agatha",
              positions: [{
                title: "Engineer"
              }]
            }])
          end
        end

        context "4 levels deep" do
          let!(:wrong_department) do
            PORO::Department.create(name: "Engineering")
          end

          let!(:department) do
            PORO::Department.create(name: "Safety")
          end

          let!(:team1) do
            PORO::Team.create(name: "Team 1", department_id: wrong_department.id)
          end

          let!(:team2) do
            PORO::Team.create(name: "Team 2", department_id: department.id)
          end

          let!(:team3) do
            PORO::Team.create(name: "Team 3", department_id: department.id)
          end

          let!(:team4) do
            PORO::Team.create(name: "Team 4", department_id: department.id)
          end

          before do
            position2.update_attributes(department_id: department.id)
          end

          it "works" do
            json = run(%|
              query getEmployees($name: String, $teamName: String) {
                employees(filter: { firstName: { eq: $name } }) {
                  id
                  firstName
                  positions {
                    title
                    department {
                      name
                      teams(filter: { name: { eq: $teamName } }) {
                        name
                      }
                    }
                  }
                }
              }
            |, {"name" => "Agatha", "teamName" => "Team 3"})
            expect(json).to eq({
              employees: [{
                firstName: "Agatha",
                id: "2",
                positions: [
                  {
                    department: {
                      name: "Safety",
                      teams: [
                        {name: "Team 3"}
                      ]
                    },
                    title: "Manager"
                  },
                  {
                    department: nil,
                    title: "Engineer"
                  },
                  {
                    department: nil,
                    title: "Old Manager"
                  }
                ]
              }]
            })
          end
        end
      end

      context "when a filter is required" do
        before do
          resource.filter :foo, :string, required: true do
            eq do |scope, value|
              scope[:conditions] ||= {}
              scope[:conditions][:first_name] = value
              scope
            end
          end
          schema!
        end

        context "and no filter is not passed" do
          it "raises schema error" do
            json = run(%(
              query {
                employees {
                  firstName
                }
              }
            ))
            expect(json[:errors][0][:message])
              .to eq("Field 'employees' is missing required arguments: filter")
          end
        end

        context "and filter is passed, but not the attribute" do
          it "raises schema error" do
            json = run(%(
              query {
                employees(filter: { lastName: { eq: "A" } }) {
                  firstName
                }
              }
            ))
            expect(json[:errors][0][:message])
              .to eq("Argument 'foo' on InputObject 'POROEmployeeFilter' is required. Expected type POROEmployeeFilterFilterfoo!")
          end
        end

        context "and filter is passed, but not the operator" do
          it "raises schema error" do
            json = run(%(
              query {
                employees(filter: { foo: { prefix: "A" } }) {
                  firstName
                }
              }
            ))
            expect(json[:errors][0][:message])
              .to eq("Argument 'eq' on InputObject 'POROEmployeeFilterFilterfoo' is required. Expected type String!")
          end
        end

        context "and it is passed" do
          it "works" do
            json = run(%|
              query {
                employees(filter: { foo: { eq: "Agatha" } }) {
                  firstName
                }
              }
            |)
            expect(json).to eq({
              employees: [{
                firstName: "Agatha"
              }]
            })
          end
        end
      end


      context "when custom type" do
        let!(:findme) do
          PORO::Employee.create(id: 999, first_name: "custom!")
        end

        before do
          type = Dry::Types::Nominal
            .new(nil)
            .constructor { |input|
              "custom!"
            }
          Graphiti::Types[:custom] = {
            read: type,
            write: type,
            params: type,
            kind: "scalar",
            description: "test",
            canonical_name: :string
          }
          resource.filter :my_custom, :custom do
            eq do |scope, value|
              scope[:conditions] ||= {}
              scope[:conditions][:first_name] = value
              scope
            end
          end
          schema!
        end

        after do
          Graphiti::Types.map.delete(:custom)
        end

        it "works" do
          json = run(%(
            query {
              employees(filter: { myCustom: { eq: "foo" } }) {
                id
                firstName
              }
            }
          ))
          expect(json).to eq({
            employees: [{
              id: "999",
              firstName: "custom!"
            }]
          })
        end
      end
    end

    describe "sorting" do
      context "via hardcoding" do
        it "works" do
          json = run(%|
            query getEmployees {
              employees(sort: [{ att: firstName, dir: asc }]) {
                firstName
              }
            }
          |)
          expect(json).to eq({
            employees: [
              {
                firstName: "Agatha"
              },
              {
                firstName: "Stephen"
              }
            ]
          })
        end
      end

      context "via variables" do
        it "works" do
          json = run(%|
            query getEmployees($sort: [POROEmployeeSort!]) {
              employees(sort: $sort) {
                firstName
              }
            }
          |, {"sort" => [{"att" => "firstName", "dir" => "asc"}]})
          expect(json).to eq({
            employees: [
              {
                firstName: "Agatha"
              },
              {
                firstName: "Stephen"
              }
            ]
          })
        end
      end

      context "when not sortable" do
        before do
          resource.class_eval do
            attribute :first_name, :string, sortable: false
          end
          schema!
        end

        it "returns error" do
          json = run(%|
            query getEmployees($sort: [POROEmployeeSort!]) {
              employees(sort: $sort) {
                firstName
              }
            }
          |, {"sort" => [{"att" => "firstName", "dir" => "asc"}]})
          expect(json).to eq({
            errors: [{
              extensions: {
                problems: [{
                  explanation: "Expected \"firstName\" to be one of: id, createdAt, today, lastName, age, change, active, salary, guardedFirstName, objekt, stringies, ints, floats, datetimes, scalarArray, objectArray",
                  path: [0, "att"]
                }],
                value: [{
                  att: "firstName",
                  dir: "asc"
                }]
              },
              locations: [
                {column: 32, line: 2}
              ],
              message: "Variable $sort of type [POROEmployeeSort!] was provided invalid value for 0.att (Expected \"firstName\" to be one of: id, createdAt, today, lastName, age, change, active, salary, guardedFirstName, objekt, stringies, ints, floats, datetimes, scalarArray, objectArray)"
            }]
          })
        end
      end

      context "when guarded" do
        context "and the guard passes" do
          it "works as normal" do
            ctx = OpenStruct.new(current_user: "admin")
            Graphiti.with_context ctx do
              json = run(%|
                query getEmployees {
                  employees(sort: [{ att: guardedFirstName, dir: asc }]) {
                    firstName
                  }
                }
              |)
              expect(json).to eq({
                employees: [
                  {firstName: "Agatha"},
                  {firstName: "Stephen"}
                ]
              })
            end
          end
        end

        context "and the guard fails" do
          it "raises error" do
            running = lambda do
              json = run(%|
                query getEmployees {
                  employees(sort: [{ att: guardedFirstName, dir: asc }]) {
                    firstName
                  }
                }
              |)
            end

            expect(running).to raise_error(
              Graphiti::Errors::InvalidAttributeAccess,
              /guarded_first_name/
            )
          end
        end
      end

      context "when on a relationship" do
        let!(:position1) do
          PORO::Position.create(title: "A", employee_id: employee1.id)
        end
        let!(:position2) do
          PORO::Position.create(title: "C", employee_id: employee1.id)
        end
        let!(:position3) do
          PORO::Position.create(title: "B", employee_id: employee1.id)
        end

        context "via hardcoding" do
          it "works" do
            json = run(%|
              query getEmployees {
                employees(filter: { firstName: { eq: "Stephen" } }) {
                  firstName
                  positions(sort: [{ att: title, dir: desc }]) {
                    title
                  }
                }
              }
            |)
            expect(json).to eq({
              employees: [{
                firstName: "Stephen",
                positions: [
                  {
                    title: "C"
                  },
                  {
                    title: "B"
                  },
                  {
                    title: "A"
                  }
                ]
              }]
            })
          end
        end

        context "via variables" do
          it "works" do
            json = run(%|
              query getEmployees($positionSort: [POROPositionSort!]) {
                employees(filter: { firstName: { eq: "Stephen" } }) {
                  firstName
                  positions(sort: $positionSort) {
                    title
                  }
                }
              }
            |, {"positionSort" => [{"att" => "title", "dir" => "desc"}]})
            expect(json).to eq({
              employees: [{
                firstName: "Stephen",
                positions: [
                  {
                    title: "C"
                  },
                  {
                    title: "B"
                  },
                  {
                    title: "A"
                  }
                ]
              }]
            })
          end
        end
      end

      context "when on relationship 4 levels deep" do
        let!(:position1) do
          PORO::Position.create title: "Position A",
                                employee_id: employee1.id,
                                department_id: department.id
        end
        let!(:department) { PORO::Department.create(name: "Dept A") }
        let!(:team1) do
          PORO::Team.create(name: "A", department_id: department.id)
        end
        let!(:team2) do
          PORO::Team.create(name: "C", department_id: department.id)
        end
        let!(:team3) do
          PORO::Team.create(name: "B", department_id: department.id)
        end

        it "works" do
          json = run(%|
            query getEmployees {
              employees(filter: { firstName: { eq: "Stephen" } }) {
                positions {
                  department {
                    teams(sort: [{ att: name, dir: desc }]) {
                      name
                    }
                  }
                }
              }
            }
          |)
          expect(json).to eq({
            employees: [{
              positions: [{
                department: {
                  teams: [{name: "C"}, {name: "B"}, {name: "A"}]
                }
              }]
            }]
          })
        end
      end
    end

    describe "paginating" do
      let!(:employee3) { PORO::Employee.create(first_name: "JK") }

      context "via hardcoding" do
        it "works" do
          json = run(%|
            query getEmployees {
              employees(page: { size: 2, number: 1 }) {
                firstName
              }
            }
          |)
          expect(json).to eq({
            employees: [
              {firstName: "Stephen"},
              {firstName: "Agatha"}
            ]
          })
          json = run(%|
            query getEmployees {
              employees(page: { size: 2, number: 2 }) {
                firstName
              }
            }
          |)
          expect(json).to eq({
            employees: [
              {firstName: "JK"}
            ]
          })
        end
      end

      context "via variables" do
        it "works" do
          json = run(%|
            query getEmployees($page: Page) {
              employees(page: $page) {
                firstName
              }
            }
          |, {"page" => {"size" => 2, "number" => 1}})
          expect(json).to eq({
            employees: [
              {firstName: "Stephen"},
              {firstName: "Agatha"}
            ]
          })
          json = run(%|
            query getEmployees {
              employees(page: { size: 2, number: 2 }) {
                firstName
              }
            }
          |, {"page" => {"size" => 2, "number" => 1}})
          expect(json).to eq({
            employees: [
              {firstName: "JK"}
            ]
          })
        end
      end

      context "on relationship" do
        let!(:position1) do
          PORO::Position.create(title: "One", employee_id: employee1.id)
        end
        let!(:position2) do
          PORO::Position.create(title: "Two", employee_id: employee1.id)
        end

        context "when one-to-many" do
          context "via hardcoding" do
            it "works" do
              json = run(%|
                query getEmployees {
                  employees(page: { size: 1 }) {
                    positions(page: { size: 1, number: 2 }) {
                      title
                    }
                  }
                }
              |)
              expect(json).to eq({
                employees: [{
                  positions: [{
                    title: "Two"
                  }]
                }]
              })
            end
          end

          context "via variables" do
            it "works" do
              json = run(%|
                query getEmployees($page: Page) {
                  employees(page: { size: 1 }) {
                    positions(page: $page) {
                      title
                    }
                  }
                }
              |, {"page" => {"size" => 1, "number" => 2}})
              expect(json).to eq({
                employees: [{
                  positions: [{
                    title: "Two"
                  }]
                }]
              })
            end
          end
        end

        context "when many records to many records" do
          it "throws error as normal" do
            running = lambda do
              run(%|
                query getEmployees($page: Page) {
                  employees(page: { size: 2 }) {
                    positions(page: $page) {
                      title
                    }
                  }
                }
              |, {"page" => {"size" => 1, "number" => 2}})
            end
            expect(running).to raise_error(
              Graphiti::Errors::SideloadQueryBuildingError,
              /UnsupportedPagination/
            )
          end
        end

        context "on a relationship 4 levels deep" do
          let!(:department) { PORO::Department.create(name: "Engineering") }
          let!(:team1) do
            PORO::Team.create(name: "One", department_id: department.id)
          end
          let!(:team2) do
            PORO::Team.create(name: "Two", department_id: department.id)
          end

          before do
            position1.update_attributes(department_id: department.id)
          end

          it "still works" do
            json = run(%|
              query getEmployees {
                employees(page: { size: 1 }) {
                  positions(page: { size: 1 }) {
                    department {
                      teams(page: { size: 1, number: 2 }) {
                        name
                      }
                    }
                  }
                }
              }
            |)
            expect(json).to eq({
              employees: [{
                positions: [{
                  department: {
                    teams: [{
                      name: "Two"
                    }]
                  }
                }]
              }]
            })
          end
        end
      end
    end

    describe "when entrypoints defined" do
      before do
        schema!([PORO::EmployeeResource])
      end

      it "works only for defined entrypoints" do
        json = run(%(
          query {
            employees {
              firstName
            }
          }
        ))
        expect(json).to eq({
          employees: [
            {firstName: "Stephen"},
            {firstName: "Agatha"}
          ]
        })
        json = run(%(
          query {
            positions {
              title
            }
          }
        ))
        expect(json[:errors][0][:message])
          .to eq("Field 'positions' doesn't exist on type 'Query'")
        schema!([PORO::PositionResource])
        json = run(%(
          query {
            positions {
              title
            }
          }
        ))
        expect(json).to eq({
          positions: []
        })
      end

      describe "via config" do
        after do
          GraphitiGraphQL::Schema.entrypoints = nil
        end

        it "respects the config" do
          json = run(%(
            query {
              employees {
                firstName
              }
            }
          ))
          expect(json).to eq({
            employees: [
              {firstName: "Stephen"},
              {firstName: "Agatha"}
            ]
          })
          json = run(%(
            query {
              positions {
                title
              }
            }
          ))
          expect(json[:errors][0][:message])
            .to eq("Field 'positions' doesn't exist on type 'Query'")
          GraphitiGraphQL::Schema.entrypoints = [PORO::PositionResource]
          schema!
          json = run(%(
            query {
              positions {
                title
              }
            }
          ))
          expect(json).to eq({
            positions: []
          })
        end
      end
    end

    describe "multiple resource entrypoints" do
      before do
        PORO::Position.create(title: "Standalone")
      end

      it "works" do
        json = run(%(
          query getPositions {
            positions {
              title
            }
          }
        ))
        expect(json).to eq({
          positions: [{
            title: "Standalone"
          }]
        })
      end
    end

    describe "unconnected resources" do
      xit "can be queried together concurrently" do
      end
    end

    describe "polymorphic resources" do
      let!(:visa) { PORO::Visa.create(id: 1, number: "1", employee_id: employee2.id) }
      let!(:gold_visa) { PORO::GoldVisa.create(id: 2, number: "2") }
      let!(:mastercard) { PORO::Mastercard.create(id: 3, number: "3") }

      it "can query at top level" do
        json = run(%(
          query {
            creditCards {
              id
              _type
              number
              description
            }
          }
        ))
        expect(json).to eq({
          credit_cards: [
            {
              id: "1",
              _type: "visas",
              number: 1,
              description: "visa description"
            },
            {
              id: "2",
              _type: "gold_visas",
              number: 2,
              description: "visa description"
            },
            {
              id: "3",
              _type: "mastercards",
              number: 3,
              description: "mastercard description"
            }
          ]
        })
      end

      it "can query as association" do
        schema!([PORO::EmployeeResource])
        json = run(%(
          query {
            employees {
              firstName
              creditCards {
                _type
                number
              }
            }
          }
        ))
        expect(json).to eq({
          employees: [
            {
              firstName: "Stephen",
              creditCards: []
            },
            {
              firstName: "Agatha",
              creditCards: [{
                _type: "visas", number: 1
              }]
            }
          ]
        })
      end

      context "when there is an additional association on the parent" do
        before do
          PORO::Transaction.create \
            amount: 100,
            credit_card_id: mastercard.id
        end

        it "can be queried via toplevel (no fragment)" do
          json = run(%(
            query {
              creditCards {
                transactions {
                  amount
                }
              }
            }
          ))
          expect(json).to eq({
            credit_cards: [
              {transactions: []},
              {transactions: []},
              {transactions: [{amount: 100}]}
            ]
          })
        end
      end

      context "when fragmenting" do
        context "when all types share a field via the parent" do
          it "only returns the field for the requesting fragment" do
            json = run(%(
              query {
                creditCards {
                  _type
                  ...on POROMastercard {
                    number
                  }
                }
              }
            ))
            expect(json).to eq({
              credit_cards: [
                {
                  _type: "visas"
                },
                {
                  _type: "gold_visas"
                },
                {
                  _type: "mastercards",
                  number: 3
                }
              ]
            })
          end
        end

        context "when only one type has the field" do
          it "only returns the field for the requesting fragment" do
            json = run(%(
              query {
                creditCards {
                  _type
                  ...on POROVisa {
                    visaOnlyAttr
                  }
                }
              }
            ))
            expect(json).to eq({
              credit_cards: [
                {
                  _type: "visas",
                  visaOnlyAttr: "visa only"
                },
                {
                  _type: "gold_visas"
                },
                {
                  _type: "mastercards"
                }
              ]
            })
          end
        end

        context "when there is an additional association requested for a single fragment" do
          context "and the relationship is defined on the parent resource" do
            before do
              PORO::Transaction.create \
                amount: 100,
                credit_card_id: visa.id
              PORO::Transaction.create \
                amount: 200,
                credit_card_id: visa.id
            end

            it "works" do
              expect_any_instance_of(PORO::TransactionResource)
                .to receive(:resolve).and_call_original
              json = run(%(
                query {
                  creditCards {
                    _type
                    ...on POROVisa {
                      transactions {
                        amount
                      }
                    }
                  }
                }
              ))
              expect(json).to eq({
                credit_cards: [
                  {
                    _type: "visas",
                    transactions: [{amount: 100}, {amount: 200}]
                  },
                  {_type: "gold_visas"},
                  {_type: "mastercards"}
                ]
              })
            end

            it "can filter the relationship" do
              json = run(%(
                query {
                  creditCards {
                    _type
                    ...on POROVisa {
                      transactions(filter: { amount: { eq: 200 } }) {
                        amount
                      }
                    }
                  }
                }
              ))
              expect(json).to eq({
                credit_cards: [
                  {
                    _type: "visas",
                    transactions: [{amount: 200}]
                  },
                  {_type: "gold_visas"},
                  {_type: "mastercards"}
                ]
              })
            end

            it "can sort the relationship" do
              json = run(%(
                query {
                  creditCards {
                    _type
                    ...on POROVisa {
                      transactions(sort: [{ att: amount, dir: desc }]) {
                        amount
                      }
                    }
                  }
                }
              ))
              expect(json).to eq({
                credit_cards: [
                  {
                    _type: "visas",
                    transactions: [{amount: 200}, {amount: 100}]
                  },
                  {_type: "gold_visas"},
                  {_type: "mastercards"}
                ]
              })
            end

            it "can paginate the relationship" do
              json = run(%(
                query {
                  creditCards(page: { size: 1 }) {
                    _type
                    ...on POROVisa {
                      transactions(page: { size: 1, number: 2 }) {
                        amount
                      }
                    }
                  }
                }
              ))
              expect(json).to eq({
                credit_cards: [
                  {
                    _type: "visas",
                    transactions: [{amount: 200}]
                  }
                ]
              })
            end
          end

          context "and the relationship is defined on multiple child resources" do
            let!(:wrong_reward) { PORO::VisaReward.create(visa_id: 999) }
            let!(:reward1) do
              PORO::VisaReward.create(visa_id: gold_visa.id, points: 5)
            end
            let!(:reward2) do
              PORO::VisaReward.create \
                visa_id: gold_visa.id,
                points: 10
            end
            let!(:transaction1) do
              PORO::VisaRewardTransaction.create(amount: 100, reward_id: reward1.id)
            end
            let!(:transaction2) do
              PORO::VisaRewardTransaction.create(amount: 200, reward_id: reward1.id)
            end

            def transactions(json)
              json[:credit_cards][1][:visaRewards][0][:rewardTransactions]
            end

            it "works" do
              expect_any_instance_of(PORO::VisaRewardResource)
                .to receive(:resolve).and_call_original
              expect_any_instance_of(PORO::VisaRewardTransactionResource)
                .to receive(:resolve).and_call_original
              json = run(%(
                query {
                  creditCards {
                    _type
                    ...on POROGoldVisa {
                      visaRewards {
                        id
                        points
                        rewardTransactions {
                          amount
                        }
                      }
                    }
                  }
                }
              ))
              expect(transactions(json)).to eq([
                {amount: 100},
                {amount: 200}
              ])
            end

            it "can filter the relationship off the fragment" do
              json = run(%(
                query {
                  creditCards {
                    _type
                    ...on POROGoldVisa {
                      visaRewards {
                        id
                        points
                        rewardTransactions(filter: { amount: { eq: 200 } }) {
                          amount
                        }
                      }
                    }
                  }
                }
              ))
              expect(transactions(json)).to eq([
                {amount: 200}
              ])
            end

            it "can sort the relationship off the fragment" do
              json = run(%(
                query {
                  creditCards {
                    _type
                    ...on POROGoldVisa {
                      visaRewards {
                        id
                        points
                        rewardTransactions(sort: [{ att: amount, dir: desc }]) {
                          amount
                        }
                      }
                    }
                  }
                }
              ))
              expect(transactions(json)).to eq([
                {amount: 200},
                {amount: 100}
              ])
            end

            it "can paginate the relationship off the fragment" do
              json = run(%(
                query {
                  creditCards(page: { size: 1, number: 2 }) {
                    _type
                    ...on POROGoldVisa {
                      visaRewards(page: { size: 1 }) {
                        id
                        points
                        rewardTransactions(page: { size: 1, number: 2 }) {
                          amount
                        }
                      }
                    }
                  }
                }
              ))
              rewards = json[:credit_cards][0][:visaRewards][0]
              expect(rewards[:rewardTransactions]).to eq([
                {amount: 200}
              ])
            end

            context "and deeply nested" do
              let!(:position) do
                PORO::Position.create(employee_id: employee2.id)
              end
              let!(:nested_gold_visa) do
                PORO::GoldVisa.create(number: "2", employee_id: employee2.id)
              end

              it "still works" do
                json = run(%(
                  query {
                    position(id: "#{position.id}") {
                      employee {
                        firstName
                        creditCards {
                          _type
                          ...on POROGoldVisa {
                            visaRewards {
                              id
                              points
                              rewardTransactions {
                                amount
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                ))
                expect(json).to eq({
                  position: {
                    employee: {
                      firstName: "Agatha",
                      creditCards: [
                        {_type: "visas"},
                        {
                          _type: "gold_visas",
                          visaRewards: [
                            {
                              id: reward1.id.to_s,
                              points: 5,
                              rewardTransactions: [
                                {amount: 100},
                                {amount: 200}
                              ]
                            },
                            {
                              id: reward2.id.to_s,
                              points: 10,
                              rewardTransactions: []
                            }
                          ]
                        }
                      ]
                    }
                  }
                })
              end
            end
          end

          context "and the relationship is defined only on a single child resource" do
            let!(:bad_mile) do
              PORO::MastercardMile.create(mastercard_id: 999)
            end

            let!(:mile) do
              PORO::MastercardMile.create(mastercard_id: mastercard.id)
            end

            it "works" do
              json = run(%(
                query {
                  creditCards {
                    _type
                    ...on POROMastercard {
                      mastercardMiles {
                        id
                        amount
                      }
                    }
                  }
                }
              ))
              expect(json).to eq({
                credit_cards: [
                  {_type: "visas"},
                  {_type: "gold_visas"},
                  {
                    _type: "mastercards",
                    mastercardMiles: [{
                      id: mile.id.to_s,
                      amount: 100
                    }]
                  }
                ]
              })
            end
          end
        end
      end
    end

    describe "polymorphic_has_many" do
      let!(:note1) do
        PORO::Note.create notable_id: employee2.id,
                          notable_type: "PORO::Employee",
                          body: "foo"
      end

      it "works" do
        json = run(%(
          query {
            employees {
              notes {
                body
              }
            }
          }
        ))
        expect(json).to eq({
          employees: [
            {
              notes: []
            },
            {
              notes: [{body: "foo"}]
            }
          ]
        })
      end
    end

    describe "polymorphic_has_many" do
      let!(:wrong_type) do
        PORO::Note.create body: "wrong",
                          notable_type: "things",
                          notable_id: employee1.id
      end
      let!(:wrong_id) do
        PORO::Note.create body: "wrong",
                          notable_type: "PORO::Employee",
                          notable_id: 999
      end
      let!(:note) do
        PORO::Note.create body: "A",
                          notable_type: "PORO::Employee",
                          notable_id: employee1.id
      end

      it "works" do
        json = run(%(
          query {
            employees {
              notes {
                body
              }
            }
          }
        ))
        expect(json).to eq({
          employees: [
            {
              notes: [{
                body: "A"
              }]
            },
            {
              notes: []
            }
          ]
        })
      end

      it "can render additional relationships" do
        PORO::NoteEdit.create \
          note_id: note.id,
          modification: "mod"
        json = run(%(
          query {
            employees {
              notes {
                body
                edits {
                  modification
                }
              }
            }
          }
        ))
        expect(json).to eq({
          employees: [
            {
              notes: [{
                body: "A",
                edits: [{
                  modification: "mod"
                }]
              }]
            },
            {
              notes: []
            }
          ]
        })
      end
    end

    describe "polymorphic_belongs_to" do
      let!(:team) do
        PORO::Team.create name: "A Team"
      end
      let!(:note1) do
        PORO::Note.create \
          notable_type: "PORO::Employee",
          notable_id: employee2.id
      end
      let!(:note2) do
        PORO::Note.create \
          notable_type: "PORO::Team",
          notable_id: team.id
      end

      it "works" do
        json = run(%(
          query {
            notes {
              id
              notable {
                id
                _type
              }
            }
          }
        ))
        expect(json).to eq({
          notes: [
            {
              id: note1.id.to_s,
              notable: {
                id: employee2.id.to_s,
                _type: "employees"
              }
            },
            {
              id: note2.id.to_s,
              notable: {
                id: team.id.to_s,
                _type: "teams"
              }
            }
          ]
        })
      end

      # TODO: this doesn't work because we pass the polymorphic fields via
      # the jsonapi type. Instead we need to do what we're doing for includes,
      # i.e. ?fields[notable.on__employees]=id,_type&fields[employees]=first_name
      #
      # If we don't want to address this, at least raise a helpful error instead
      # of returning the wrong payload
      context "when listing parent > child > parent" do
        context "when not fragmenting" do
          xit "respects fieldsets" do
            json = run(%(
              query {
                employee(id: "#{employee1.id}") {
                  firstName
                  notes {
                    notable {
                      id
                      _type
                    }
                  }
                }
              }
            ))
            expect(json).to eq({
              employee: {
                firstName: "Stephen",
                notes: [{
                  notable: {
                    id: employee1.id.to_s,
                    _type: "employees"
                  }
                }]
              }
            })
          end
        end
      end

      context "when fragmenting" do
        it "can load fragment-specific fields" do
          json = run(%(
            query {
              notes {
                id
                notable {
                  id
                  ...on POROEmployee {
                    firstName
                  }
                  ...on POROTeam {
                    _type
                    name
                  }
                }
              }
            }
          ))
          expect(json).to eq({
            notes: [
              {
                id: note1.id.to_s,
                notable: {
                  id: employee2.id.to_s,
                  firstName: "Agatha"
                }
              },
              {
                id: note2.id.to_s,
                notable: {
                  id: team.id.to_s,
                  _type: "teams",
                  name: "A Team"
                }
              }
            ]
          })
        end

        context "when a fragment-specific relationship" do
          before do
            PORO::Position.create \
              title: "foo",
              employee_id: employee2.id,
              active: true
            PORO::Position.create \
              title: "bar",
              employee_id: employee2.id,
              active: false
          end

          def positions(json)
            json[:notes][0][:notable][:positions]
          end

          it "can load" do
            expect_any_instance_of(PORO::PositionResource)
              .to receive(:resolve).and_call_original
            json = run(%(
              query {
                notes {
                  id
                  notable {
                    id
                    ...on POROEmployee {
                      firstName
                      positions {
                        title
                      }
                    }
                    ...on POROTeam {
                      _type
                      name
                    }
                  }
                }
              }
            ))
            expect(positions(json)).to eq([
              {title: "foo"},
              {title: "bar"}
            ])
          end

          it "can filter a relationship off the fragment" do
            json = run(%(
              query {
                notes {
                  id
                  notable {
                    id
                    ...on POROEmployee {
                      firstName
                      positions(filter: { active: { eq: true } }) {
                        title
                      }
                    }
                    ...on POROTeam {
                      _type
                      name
                    }
                  }
                }
              }
            ))
            expect(positions(json)).to eq([
              {title: "foo"}
            ])
          end

          it "can sort a relationship off the fragment" do
            json = run(%(
              query {
                notes {
                  id
                  notable {
                    id
                    ...on POROEmployee {
                      firstName
                      positions(sort: [{ att: title, dir: asc }]) {
                        title
                      }
                    }
                    ...on POROTeam {
                      _type
                      name
                    }
                  }
                }
              }
            ))
            expect(positions(json)).to eq([
              {title: "bar"},
              {title: "foo"}
            ])
          end

          it "can paginate a relationship off the fragment" do
            json = run(%(
              query {
                notes {
                  id
                  notable {
                    id
                    ...on POROEmployee {
                      firstName
                      positions(page: { size: 1, number: 2 }) {
                        title
                      }
                    }
                    ...on POROTeam {
                      _type
                      name
                    }
                  }
                }
              }
            ))
            expect(positions(json)).to eq([
              {title: "bar"}
            ])
          end
        end
      end
    end

    context "when max_depth is set" do
      before do
        GraphitiGraphQL.schemas.graphql.max_depth(2)
      end

      it "is respected" do
        json = run(%(
          query {
            employees {
              positions {
                department {
                  name
                }
              }
            }
          }
        ))
        expect(json).to eq({
          errors: [{
            message: "Query has depth of 4, which exceeds max depth of 2"
          }]
        })
      end
    end
  end
end
