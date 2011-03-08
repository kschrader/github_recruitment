require 'rubygems'
require 'net/http'
require 'yaml'
require 'cgi'
require 'bossman'
include Java
include BOSSMan

jars = Dir['./lib/*.jar']
jars.each do |jar| 
  require jar
end

java_import Java::edu.uci.ics.jung.graph.DirectedSparseGraph
java_import Java::edu.uci.ics.jung.algorithms.importance.BetweennessCentrality
java_import Java::edu.uci.ics.jung.graph.util.EdgeType

$stdout.sync = true
BOSSMan.application_id = YAML.load_file("config.yml")['yahookey']
urls = []
location = ARGV[0]

if location == 'New York'
  aggregated_locations = ['Brooklyn', 'New York', 'Queens']
else
  aggregated_locations = [location]
end

aggregated_locations.each do |individual_location|
  puts "Finding developers in #{individual_location}"
  puts "---"
  offset = 0
  done = false
  
  while !done
      results = BOSSMan::Search.web('site:github.com location "' + individual_location + '" "profile - github"', :start => offset)
      offset += results.count.to_i
      if offset > results.totalhits.to_i
          done = true
      end
      urls += results.results.map { |r| r.url }
  end
end

puts "Getting social graph"
network = {}
Net::HTTP.start('github.com') { |http|
    for line in urls
        sleep 1
        line.match(/github.com\/([a-zA-Z0-9-]+)/)
        me = $1
        if me.match(/^(.*)\/$/)
            me = $1
        end
        url = "/api/v2/yaml/user/show/#{me}/followers"
        puts url
        req = Net::HTTP::Get.new(url)
        response = http.request(req)
        case response 
        when Net::HTTPSuccess
            network[me] = []
            for link in YAML.load(response.body)["users"]
                network[me] << link
            end
        else
            puts "non-200: #{me}"
        end
    end
}

puts 'Ranking results'

network_graph = DirectedSparseGraph.new
count = 0

network.each do |node|
  user = node[0]
  follows = node[1]
  follows.each do |followed_user|
    network_graph.addEdge(count, user, followed_user, EdgeType::DIRECTED)
    count = count + 1
  end
end

ranker = BetweennessCentrality.new(network_graph)
result = Hash.new

ranker.setRemoveRankScoresOnFinalize(false)
ranker.evaluate

network_graph.getVertices.each do |vertice|
  result[vertice] = ranker.getVertexRankScore(vertice)
end

ranker = Java::Ranker.new
p ranker
for user in result.sort_by { |user,score| score }
    puts "#{user[0]} = #{user[1]}"
end
