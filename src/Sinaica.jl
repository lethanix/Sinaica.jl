module Sinaica

using Gumbo, HTTP, JSON, Logging, Dates
using ProgressMeter

export data, stationsData

#*###############################################
#*--> Global Variables.

# Criteria pollutants
const criteriaPollutants = ["CO", "NO2", "O3", "SO2", "PM10", "PM2.5"]


#*###############################################
#*--> Functions.

#*###############################################
#*--> Fetch data.
function retrieveData(url::String,
                    rgx::Regex,
                    method::String="GET",
                    headers::Dict=Dict(),
                    body::Dict=Dict())
    #* Description:
    #*      Obtains the information from the url with the
    #*      given regular expression (rgx).
    #*      Defaults:
    #*          method  -> GET
    #*          headers -> empty Dict
    #*          body    -> empty Dict

    if uppercase(method) == "POST"
        body = try HTTP.URIs.escapeuri(body) catch err; @error err end
        response = try HTTP.post(url, headers, body) catch err; @error err end
        while isnothing(response)
            response = try HTTP.post(url, headers, body) catch err; @error err end
        end
    else
        response = try HTTP.get(url) catch err; @error err end
        while isnothing(response)
            response = try HTTP.post(url, headers, body) catch err; @error err end
        end
    end

    # Extract the HTML source code from the url.
    html = parsehtml(String(response.body))

    # Find the data using regex, parse it & return it as a Dictionary.
    dataJSON = match(rgx, string(html.root) ).captures[1]
    dataDict = JSON.parse(dataJSON)

    return dataDict

end #* End of retrieveData()

#*###############################################
#*--> Organize data.
function sortData(inputData)
    #* Description:
    #*      Filter & organize the general information obtained from SINAICA.

    sortedData = []
    prog = Progress(length(inputData), "Processing general data... ")
    for state in inputData
        #ProgressMeter.next!(prog; showvalues = [(:State, state["nom"])])
        # Filter the data.
        if isnothing( tryparse(Float64, string(state[1])) )
            ProgressMeter.next!(prog; showvalues = [(:Its_Not_A_State, state.first)]) 
            continue
        end

        ProgressMeter.next!(prog; showvalues = [(:State, state.second["nom"])])

		# Get the networks of the state.
		networksList = []
		foreach(state[2]["redes"]) do network

			# Get the stations of the network & save them in 'stationsList'.
			stationsList = []
			foreach(network[2]["ests"]) do station
				push!(stationsList, Dict("ID" => station[1],
								  	"NOMBRE" => station[2]["nom"],
								  	"CODIGO" => station[2]["cod"],
									"GPS" => Dict("LAT" => station[2]["lat"],
                                            "LNG" => station[2]["long"]),
                                    "CONTAMINANTES" => Dict() )													)
			end

			# Save the network in 'networksList'.
			push!(networksList, Dict("ID" => network[1],
								"NOMBRE" => network[2]["nom"],
								"CODIGO" => network[2]["cod"],
								"ESTACIONES" => stationsList) )
		end

		# Save the state data in 'data'.
		stateData = Dict("ID" => state[1],
						"NOMBRE" => state[2]["nom"],
						"CODIGO" => state[2]["cod"],
						"GPS" => Dict("LAT" => state[2]["lat"],
								"LNG" => state[2]["long"]),
						"REDES" => networksList )

        push!(sortedData,stateData)
    end

    return sortedData

end #* End of function sortData()

#*###############################################
#*--> Fetch station pollutants data.
function getPollutants(stationID,
                    startDate::String = string(Dates.today()),
                    timeWindow::Int = 1)
    #* Description:
    #*      Request data starting from specific date and time window.
    #*      startDate => YYYY-MM-DD
    #*      timeWindow:
    #*          1 => day,
    #*          2 => 1 week,
    #*          3 => 2 weeks,
    #*          4 => month

    # Info necessary for function retrieveData()
    url = "https://sinaica.inecc.gob.mx/pags/datGrafs.php"
    headers = Dict("Content-Type" => "application/x-www-form-urlencoded", "charset" => "UTF-8") 
    rgx = r"^.+var dat = (.+);$"am

    pollutantsData = Dict()
    for pollutant in criteriaPollutants
        params = Dict("estacionId" => stationID,
                    "param" => pollutant,
                    "fechaIni" => startDate,
                    "rango" => timeWindow,
                    "tipoDatos" => "")

        pollutantsData[pollutant] = retrieveData(url, rgx, "POST", headers, params)
    end

    return pollutantsData

end #* End of function getPollutants()

#*###############################################
#*--> Fetch station's data from a state.
function stationsData(state::String,
                    save::Bool=false,
                    startDate::String = string(Dates.today()),
                    timeWindow::Int = 1)

    #* Description:
    #*      Request data of the stations from the state,
    #*      starting from specific date and time window.
    #*      If save == true, the info will be saved in
    #*      the global data.
    #*
    #*      state => state_name_as_string
    #*      save => Boolean
    #*      startDate => YYYY-MM-DD
    #*      timeWindow:
    #*          1 => day,
    #*          2 => 1 week,
    #*          3 => 2 weeks,
    #*          4 => month

    state = uppercase(state)

    # Find the index of the state in the data.
    idx = findfirst(x -> uppercase(x["NOMBRE"]) == state, data[1:end])

    # Loop through each station in the state & get its data.
    stationData = []
    @info "Obtaining data from stations in $(data[idx]["NOMBRE"])"
    for network in data[idx]["REDES"]
        # Display info in the terminal.
        @info "***** Network: $(network["NOMBRE"])"
        prog = Progress(length(network["ESTACIONES"]), "Getting station data... ")

        # Save the info in 'stationData' & the global data.
        if save == true
            map(network["ESTACIONES"]) do s
                s["CONTAMINANTES"] =  getPollutants(s["ID"], startDate, timeWindow)
                ProgressMeter.next!(prog; showvalues = [(:Station, s["NOMBRE"]), (:ID,s["ID"]) ] )
                push!(stationData, s)
            end
            continue
        end

        # If save != true, it only save the info in 'stationData'
        for s in network["ESTACIONES"]
            merged = merge(s, Dict("CONTAMINANTES" => getPollutants(s["ID"], startDate, timeWindow)) )
            ProgressMeter.next!(prog; showvalues = [(:Station, s["NOMBRE"]), (:ID,s["ID"]) ] )
            push!(stationData, merged)
        end
    end

    return stationData

end #* End of function stationsData()

#*###############################################
#*--> Initial process.
begin
    url = "https://sinaica.inecc.gob.mx/index.php"
    rgx = r"^.+var cump = (.+);$"am

    @info "Obtainig general data from $(url)"
    global data = retrieveData(url, rgx) |> sortData
end

end #* End of module Sinaica