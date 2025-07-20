# frozen_string_literal: true

module ExcelAnalysis
  module Services
    # 수식 의존성 그래프 시각화 서비스
    # HyperFormula 기반 의존성 분석 및 D3.js/Cytoscape 등의 시각화 라이브러리용 데이터 생성
    class DependencyGraphService
      include ActiveModel::Model

      # 의존성 그래프 관련 오류
      class DependencyAnalysisError < StandardError; end
      class GraphGenerationError < StandardError; end
      class CircularReferenceError < StandardError; end

      # 그래프 레이아웃 유형
      LAYOUT_TYPES = {
        hierarchical: {
          name: "계층형",
          description: "의존성 계층에 따른 트리 구조",
          algorithm: "dagre"
        },
        force_directed: {
          name: "힘 기반",
          description: "노드 간 인력과 반발력을 이용한 자연스러운 배치",
          algorithm: "force"
        },
        circular: {
          name: "원형",
          description: "원형 배치로 관계를 명확히 표시",
          algorithm: "circle"
        },
        grid: {
          name: "격자형",
          description: "셀 위치를 반영한 격자 배치",
          algorithm: "grid"
        },
        breadthfirst: {
          name: "너비우선",
          description: "선택된 노드부터 너비우선 탐색 순서로 배치",
          algorithm: "breadthfirst"
        }
      }.freeze

      # 노드 유형
      NODE_TYPES = {
        formula_cell: {
          color: "#4CAF50",
          shape: "ellipse",
          icon: "formula"
        },
        data_cell: {
          color: "#2196F3",
          shape: "rectangle",
          icon: "data"
        },
        range: {
          color: "#FF9800",
          shape: "diamond",
          icon: "range"
        },
        external_reference: {
          color: "#9C27B0",
          shape: "triangle",
          icon: "external"
        },
        error_cell: {
          color: "#F44336",
          shape: "star",
          icon: "error"
        }
      }.freeze

      # 엣지 유형
      EDGE_TYPES = {
        direct_dependency: {
          color: "#666666",
          width: 2,
          style: "solid",
          arrow: "triangle"
        },
        indirect_dependency: {
          color: "#CCCCCC",
          width: 1,
          style: "dashed",
          arrow: "triangle"
        },
        circular_reference: {
          color: "#F44336",
          width: 3,
          style: "solid",
          arrow: "circle"
        },
        cross_sheet: {
          color: "#9C27B0",
          width: 2,
          style: "dotted",
          arrow: "triangle"
        }
      }.freeze

      attr_reader :formula_engine_client

      def initialize
        @formula_engine_client = FormulaEngineClient.instance
      end

      # 의존성 그래프 생성
      # @param excel_file [ExcelFile] 분석할 Excel 파일
      # @param options [Hash] 그래프 생성 옵션
      # @return [Common::Result] 의존성 그래프 데이터
      def generate_dependency_graph(excel_file, options = {})
        Rails.logger.info("의존성 그래프 생성 시작: #{excel_file.id}")

        graph_data = {
          metadata: {
            excel_file_id: excel_file.id,
            filename: excel_file.filename,
            generated_at: Time.current,
            layout_type: options[:layout] || "hierarchical",
            analysis_options: options
          },
          nodes: [],
          edges: [],
          layout_config: {},
          statistics: {},
          circular_references: [],
          critical_paths: [],
          recommendations: []
        }

        begin
          # 1. Excel 파일 분석
          analysis_result = analyze_excel_dependencies(excel_file, options)
          return analysis_result if analysis_result.failure?

          dependency_analysis = analysis_result.value

          # 2. 노드 생성
          nodes_result = generate_nodes(dependency_analysis, options)
          return nodes_result if nodes_result.failure?

          graph_data[:nodes] = nodes_result.value

          # 3. 엣지 생성
          edges_result = generate_edges(dependency_analysis, graph_data[:nodes], options)
          return edges_result if edges_result.failure?

          graph_data[:edges] = edges_result.value

          # 4. 순환 참조 탐지 및 표시
          circular_refs = detect_and_visualize_circular_references(dependency_analysis)
          graph_data[:circular_references] = circular_refs

          # 5. 주요 경로 식별
          critical_paths = identify_critical_paths(graph_data[:nodes], graph_data[:edges])
          graph_data[:critical_paths] = critical_paths

          # 6. 레이아웃 설정 생성
          layout_config = generate_layout_config(options[:layout] || "hierarchical", graph_data)
          graph_data[:layout_config] = layout_config

          # 7. 그래프 통계 계산
          statistics = calculate_graph_statistics(graph_data)
          graph_data[:statistics] = statistics

          # 8. 최적화 권장사항 생성
          recommendations = generate_graph_recommendations(graph_data, dependency_analysis)
          graph_data[:recommendations] = recommendations

          # 9. 필터링 및 클러스터링 적용
          if options[:apply_filters]
            graph_data = apply_graph_filters(graph_data, options[:filters] || {})
          end

          if options[:apply_clustering]
            graph_data[:clusters] = generate_graph_clusters(graph_data)
          end

          Common::Result.success(graph_data)

        rescue StandardError => e
          Rails.logger.error("의존성 그래프 생성 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "의존성 그래프 생성 실패: #{e.message}",
              code: "DEPENDENCY_GRAPH_ERROR",
              details: { excel_file_id: excel_file.id, options: options }
            )
          )
        end
      end

      # 대화형 그래프 데이터 생성 (부분 로딩)
      # @param excel_file [ExcelFile] Excel 파일
      # @param focus_cell [String] 중심 셀 (예: A1, Sheet1!B2)
      # @param depth [Integer] 탐색 깊이
      # @return [Common::Result] 부분 그래프 데이터
      def generate_interactive_subgraph(excel_file, focus_cell, depth = 2)
        Rails.logger.info("대화형 서브그래프 생성: #{excel_file.id} - #{focus_cell} (depth: #{depth})")

        begin
          # 중심 셀부터 지정된 깊이까지의 의존성만 추출
          subgraph_analysis = analyze_cell_dependencies(excel_file, focus_cell, depth)
          return subgraph_analysis if subgraph_analysis.failure?

          # 서브그래프 데이터 생성
          subgraph_data = {
            focus_cell: focus_cell,
            depth: depth,
            nodes: [],
            edges: [],
            navigation_info: {},
            expansion_hints: [],
            performance_metrics: {}
          }

          dependency_data = subgraph_analysis.value

          # 노드 및 엣지 생성
          nodes_result = generate_nodes(dependency_data, { focus_mode: true })
          return nodes_result if nodes_result.failure?

          edges_result = generate_edges(dependency_data, nodes_result.value, { focus_mode: true })
          return edges_result if edges_result.failure?

          subgraph_data[:nodes] = nodes_result.value
          subgraph_data[:edges] = edges_result.value

          # 네비게이션 정보 생성
          subgraph_data[:navigation_info] = generate_navigation_info(focus_cell, dependency_data)

          # 확장 힌트 생성 (더 탐색할 수 있는 노드들)
          subgraph_data[:expansion_hints] = generate_expansion_hints(dependency_data, depth)

          # 성능 메트릭
          subgraph_data[:performance_metrics] = {
            node_count: subgraph_data[:nodes].length,
            edge_count: subgraph_data[:edges].length,
            generation_time: Time.current
          }

          Common::Result.success(subgraph_data)

        rescue StandardError => e
          Rails.logger.error("대화형 서브그래프 생성 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "서브그래프 생성 실패: #{e.message}",
              code: "SUBGRAPH_GENERATION_ERROR",
              details: { excel_file_id: excel_file.id, focus_cell: focus_cell, depth: depth }
            )
          )
        end
      end

      # 그래프 메트릭 계산
      # @param graph_data [Hash] 그래프 데이터
      # @return [Common::Result] 그래프 메트릭
      def calculate_graph_metrics(graph_data)
        Rails.logger.info("그래프 메트릭 계산 시작")

        begin
          metrics = {
            structural_metrics: {},
            dependency_metrics: {},
            complexity_metrics: {},
            centrality_metrics: {},
            path_metrics: {}
          }

          nodes = graph_data[:nodes]
          edges = graph_data[:edges]

          # 구조적 메트릭
          metrics[:structural_metrics] = {
            node_count: nodes.length,
            edge_count: edges.length,
            density: calculate_graph_density(nodes, edges),
            average_degree: calculate_average_degree(nodes, edges),
            max_degree: calculate_max_degree(nodes, edges)
          }

          # 의존성 메트릭
          metrics[:dependency_metrics] = {
            dependency_depth: calculate_dependency_depth(graph_data),
            fanout_distribution: calculate_fanout_distribution(nodes, edges),
            fanin_distribution: calculate_fanin_distribution(nodes, edges),
            dependency_chains: identify_dependency_chains(graph_data)
          }

          # 복잡도 메트릭
          metrics[:complexity_metrics] = {
            cyclomatic_complexity: calculate_cyclomatic_complexity(nodes, edges),
            component_count: count_connected_components(graph_data),
            clustering_coefficient: calculate_clustering_coefficient(graph_data)
          }

          # 중심성 메트릭
          metrics[:centrality_metrics] = {
            degree_centrality: calculate_degree_centrality(nodes, edges),
            betweenness_centrality: calculate_betweenness_centrality(graph_data),
            closeness_centrality: calculate_closeness_centrality(graph_data)
          }

          # 경로 메트릭
          metrics[:path_metrics] = {
            shortest_paths: calculate_shortest_paths(graph_data),
            diameter: calculate_graph_diameter(graph_data),
            average_path_length: calculate_average_path_length(graph_data)
          }

          Common::Result.success(metrics)

        rescue StandardError => e
          Rails.logger.error("그래프 메트릭 계산 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "그래프 메트릭 계산 실패: #{e.message}",
              code: "GRAPH_METRICS_ERROR"
            )
          )
        end
      end

      # 그래프 시각화용 JSON 내보내기
      # @param graph_data [Hash] 그래프 데이터
      # @param format [String] 출력 형식 (cytoscape, d3, vis, etc.)
      # @return [Common::Result] 형식화된 그래프 데이터
      def export_graph_for_visualization(graph_data, format = "cytoscape")
        Rails.logger.info("그래프 시각화 데이터 내보내기: #{format}")

        begin
          case format.downcase
          when "cytoscape"
            exported_data = export_for_cytoscape(graph_data)
          when "d3"
            exported_data = export_for_d3(graph_data)
          when "vis"
            exported_data = export_for_vis_js(graph_data)
          when "graphviz"
            exported_data = export_for_graphviz(graph_data)
          else
            return Common::Result.failure(
              Common::Errors::ValidationError.new(
                message: "지원하지 않는 형식: #{format}",
                details: { supported_formats: [ "cytoscape", "d3", "vis", "graphviz" ] }
              )
            )
          end

          Common::Result.success({
            format: format,
            data: exported_data,
            metadata: {
              node_count: graph_data[:nodes].length,
              edge_count: graph_data[:edges].length,
              exported_at: Time.current
            }
          })

        rescue StandardError => e
          Rails.logger.error("그래프 내보내기 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "그래프 내보내기 실패: #{e.message}",
              code: "GRAPH_EXPORT_ERROR",
              details: { format: format }
            )
          )
        end
      end

      private

      # Excel 의존성 분석
      def analyze_excel_dependencies(excel_file, options)
        # FormulaAnalysisService를 통한 기본 분석
        analysis_service = FormulaAnalysisService.new(excel_file)
        analysis_result = analysis_service.analyze
        return analysis_result if analysis_result.failure?

        formula_analysis = analysis_result.value[:formula_analysis]

        # HyperFormula를 통한 상세 의존성 분석
        dependency_result = analyze_detailed_dependencies(excel_file, formula_analysis, options)
        return dependency_result if dependency_result.failure?

        detailed_dependencies = dependency_result.value

        # 의존성 데이터 통합
        integrated_analysis = {
          basic_analysis: formula_analysis,
          detailed_dependencies: detailed_dependencies,
          dependency_matrix: build_dependency_matrix(detailed_dependencies),
          cell_metadata: extract_cell_metadata(formula_analysis),
          cross_sheet_dependencies: identify_cross_sheet_dependencies(detailed_dependencies)
        }

        Common::Result.success(integrated_analysis)
      end

      # 상세 의존성 분석 (HyperFormula 활용)
      def analyze_detailed_dependencies(excel_file, formula_analysis, options)
        begin
          # 임시로 간단한 의존성 구조 생성 (실제로는 HyperFormula API 사용)
          detailed_deps = {
            cells: {},
            dependencies: {},
            dependents: {},
            ranges: {},
            external_references: {}
          }

          # 수식 셀들의 의존성 분석
          if formula_analysis&.dig("formulas")
            formula_analysis["formulas"].each do |formula_info|
              cell_id = formula_info["cell"]
              formula = formula_info["formula"]

              # 의존성 추출
              dependencies = extract_cell_dependencies(formula)
              detailed_deps[:dependencies][cell_id] = dependencies

              # 역방향 의존성 구성
              dependencies.each do |dep_cell|
                detailed_deps[:dependents][dep_cell] ||= []
                detailed_deps[:dependents][dep_cell] << cell_id
              end

              # 셀 정보 저장
              detailed_deps[:cells][cell_id] = {
                formula: formula,
                type: determine_cell_type(formula),
                complexity: calculate_cell_complexity(formula),
                sheet: extract_sheet_name(cell_id)
              }
            end
          end

          Common::Result.success(detailed_deps)

        rescue StandardError => e
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "상세 의존성 분석 실패: #{e.message}",
              code: "DETAILED_DEPENDENCY_ERROR"
            )
          )
        end
      end

      # 특정 셀의 의존성 분석
      def analyze_cell_dependencies(excel_file, focus_cell, depth)
        analysis_result = analyze_excel_dependencies(excel_file, {})
        return analysis_result if analysis_result.failure?

        full_analysis = analysis_result.value

        # BFS를 사용해서 지정된 깊이까지의 의존성만 추출
        subgraph_deps = extract_subgraph_dependencies(full_analysis, focus_cell, depth)

        Common::Result.success(subgraph_deps)
      end

      # 노드 생성
      def generate_nodes(dependency_analysis, options)
        nodes = []

        dependency_analysis[:detailed_dependencies][:cells].each do |cell_id, cell_info|
          node = {
            id: cell_id,
            label: generate_node_label(cell_id, cell_info),
            type: cell_info[:type],
            data: {
              formula: cell_info[:formula],
              complexity: cell_info[:complexity],
              sheet: cell_info[:sheet],
              cell_reference: cell_id
            },
            style: generate_node_style(cell_info[:type], cell_info[:complexity]),
            position: generate_node_position(cell_id, options)
          }

          # 포커스 모드에서는 중심 노드 강조
          if options[:focus_mode] && options[:focus_cell] == cell_id
            node[:style][:highlighted] = true
            node[:style][:border_width] = 4
          end

          nodes << node
        end

        Common::Result.success(nodes)
      end

      # 엣지 생성
      def generate_edges(dependency_analysis, nodes, options)
        edges = []
        edge_id_counter = 0

        dependency_analysis[:detailed_dependencies][:dependencies].each do |source_cell, target_cells|
          target_cells.each do |target_cell|
            # 노드가 존재하는지 확인
            source_exists = nodes.any? { |n| n[:id] == source_cell }
            target_exists = nodes.any? { |n| n[:id] == target_cell }

            next unless source_exists && target_exists

            edge_type = determine_edge_type(source_cell, target_cell, dependency_analysis)

            edge = {
              id: "edge_#{edge_id_counter += 1}",
              source: target_cell, # 의존성 방향: target -> source
              target: source_cell,
              type: edge_type,
              data: {
                dependency_type: edge_type,
                strength: calculate_dependency_strength(source_cell, target_cell, dependency_analysis)
              },
              style: generate_edge_style(edge_type)
            }

            edges << edge
          end
        end

        Common::Result.success(edges)
      end

      # 순환 참조 탐지 및 시각화
      def detect_and_visualize_circular_references(dependency_analysis)
        circular_refs = []

        # 간단한 순환 참조 탐지 알고리즘
        dependencies = dependency_analysis[:detailed_dependencies][:dependencies]

        dependencies.each do |cell, deps|
          circular_path = find_circular_path(cell, deps, dependencies, [])
          if circular_path.any?
            circular_refs << {
              id: SecureRandom.uuid,
              path: circular_path,
              severity: calculate_circular_reference_severity(circular_path),
              impact: assess_circular_reference_impact(circular_path, dependency_analysis)
            }
          end
        end

        circular_refs
      end

      # 주요 경로 식별
      def identify_critical_paths(nodes, edges)
        critical_paths = []

        # 입력 노드 (의존성이 없는 노드)들 식별
        input_nodes = identify_input_nodes(nodes, edges)

        # 출력 노드 (다른 노드가 의존하지 않는 노드)들 식별
        output_nodes = identify_output_nodes(nodes, edges)

        # 입력에서 출력까지의 경로 중 가장 긴 경로들 식별
        input_nodes.each do |input_node|
          output_nodes.each do |output_node|
            path = find_longest_path(input_node, output_node, edges)
            if path.length > 3 # 의미있는 길이의 경로만
              critical_paths << {
                id: SecureRandom.uuid,
                start: input_node,
                end: output_node,
                path: path,
                length: path.length,
                impact_score: calculate_path_impact_score(path, nodes)
              }
            end
          end
        end

        # 영향도 순으로 정렬
        critical_paths.sort_by { |path| -path[:impact_score] }.first(10)
      end

      # 레이아웃 설정 생성
      def generate_layout_config(layout_type, graph_data)
        base_config = LAYOUT_TYPES[layout_type.to_sym] || LAYOUT_TYPES[:hierarchical]

        config = {
          name: base_config[:algorithm],
          algorithm: base_config[:algorithm],
          options: {}
        }

        case layout_type.to_sym
        when :hierarchical
          config[:options] = {
            name: "dagre",
            rankDir: "TB",
            align: "center",
            ranker: "tight-tree",
            nodeSep: 50,
            rankSep: 100
          }
        when :force_directed
          config[:options] = {
            name: "cose",
            idealEdgeLength: 100,
            nodeOverlap: 20,
            refresh: 20,
            fit: true,
            padding: 30,
            randomize: false,
            componentSpacing: 100,
            nodeRepulsion: 400000,
            edgeElasticity: 100,
            nestingFactor: 5
          }
        when :circular
          config[:options] = {
            name: "circle",
            fit: true,
            padding: 30,
            boundingBox: { x1: 0, y1: 0, w: 1, h: 1 },
            avoidOverlap: true,
            radius: nil
          }
        when :grid
          config[:options] = {
            name: "grid",
            fit: true,
            padding: 30,
            boundingBox: { x1: 0, y1: 0, w: 1, h: 1 },
            avoidOverlap: true,
            rows: nil,
            cols: nil
          }
        end

        config
      end

      # 그래프 통계 계산
      def calculate_graph_statistics(graph_data)
        nodes = graph_data[:nodes]
        edges = graph_data[:edges]

        {
          node_count: nodes.length,
          edge_count: edges.length,
          density: calculate_graph_density(nodes, edges),
          average_degree: calculate_average_degree(nodes, edges),
          max_depth: calculate_max_dependency_depth(graph_data),
          circular_reference_count: graph_data[:circular_references].length,
          critical_path_count: graph_data[:critical_paths].length,
          node_type_distribution: calculate_node_type_distribution(nodes),
          edge_type_distribution: calculate_edge_type_distribution(edges),
          complexity_distribution: calculate_complexity_distribution(nodes)
        }
      end

      # 그래프 권장사항 생성
      def generate_graph_recommendations(graph_data, dependency_analysis)
        recommendations = []

        # 순환 참조 경고
        if graph_data[:circular_references].any?
          recommendations << {
            type: "circular_reference_warning",
            priority: "high",
            message: "#{graph_data[:circular_references].length}개의 순환 참조가 발견되었습니다.",
            action: "순환 참조를 해결하여 계산 오류를 방지하세요.",
            affected_cells: graph_data[:circular_references].flat_map { |cr| cr[:path] }.uniq
          }
        end

        # 복잡도 경고
        high_complexity_nodes = graph_data[:nodes].select { |n| n[:data][:complexity] > 7.0 }
        if high_complexity_nodes.any?
          recommendations << {
            type: "complexity_warning",
            priority: "medium",
            message: "#{high_complexity_nodes.length}개의 고복잡도 수식이 발견되었습니다.",
            action: "복잡한 수식을 단순화하여 유지보수성을 향상시키세요.",
            affected_cells: high_complexity_nodes.map { |n| n[:id] }
          }
        end

        # 긴 의존성 체인 경고
        long_chains = graph_data[:critical_paths].select { |path| path[:length] > 5 }
        if long_chains.any?
          recommendations << {
            type: "long_dependency_chain",
            priority: "medium",
            message: "#{long_chains.length}개의 긴 의존성 체인이 발견되었습니다.",
            action: "의존성 체인을 줄여 계산 성능을 향상시키세요.",
            affected_paths: long_chains.map { |chain| chain[:path] }
          }
        end

        recommendations
      end

      # 그래프 필터 적용
      def apply_graph_filters(graph_data, filters)
        filtered_data = graph_data.deep_dup

        # 복잡도 필터
        if filters[:min_complexity] || filters[:max_complexity]
          min_complexity = filters[:min_complexity] || 0
          max_complexity = filters[:max_complexity] || Float::INFINITY

          filtered_data[:nodes].select! do |node|
            complexity = node[:data][:complexity] || 0
            complexity >= min_complexity && complexity <= max_complexity
          end

          # 필터링된 노드에 연결된 엣지만 유지
          node_ids = filtered_data[:nodes].map { |n| n[:id] }
          filtered_data[:edges].select! do |edge|
            node_ids.include?(edge[:source]) && node_ids.include?(edge[:target])
          end
        end

        # 시트 필터
        if filters[:sheets].present?
          filtered_data[:nodes].select! do |node|
            filters[:sheets].include?(node[:data][:sheet])
          end

          node_ids = filtered_data[:nodes].map { |n| n[:id] }
          filtered_data[:edges].select! do |edge|
            node_ids.include?(edge[:source]) && node_ids.include?(edge[:target])
          end
        end

        filtered_data
      end

      # 그래프 클러스터링
      def generate_graph_clusters(graph_data)
        clusters = []

        # 시트별 클러스터링
        sheet_clusters = group_nodes_by_sheet(graph_data[:nodes])
        sheet_clusters.each_with_index do |(sheet, nodes), index|
          clusters << {
            id: "sheet_cluster_#{index}",
            name: "Sheet: #{sheet}",
            type: "sheet",
            nodes: nodes.map { |n| n[:id] },
            color: generate_cluster_color(index)
          }
        end

        # 기능별 클러스터링 (복잡도 기반)
        complexity_clusters = group_nodes_by_complexity(graph_data[:nodes])
        complexity_clusters.each_with_index do |(level, nodes), index|
          clusters << {
            id: "complexity_cluster_#{index}",
            name: "Complexity: #{level}",
            type: "complexity",
            nodes: nodes.map { |n| n[:id] },
            color: generate_complexity_color(level)
          }
        end

        clusters
      end

      # 시각화 형식별 내보내기 메소드들

      def export_for_cytoscape(graph_data)
        {
          elements: {
            nodes: graph_data[:nodes].map do |node|
              {
                data: {
                  id: node[:id],
                  label: node[:label],
                  type: node[:type],
                  **node[:data]
                },
                position: node[:position],
                style: node[:style]
              }
            end,
            edges: graph_data[:edges].map do |edge|
              {
                data: {
                  id: edge[:id],
                  source: edge[:source],
                  target: edge[:target],
                  type: edge[:type],
                  **edge[:data]
                },
                style: edge[:style]
              }
            end
          },
          layout: graph_data[:layout_config],
          style: generate_cytoscape_stylesheet()
        }
      end

      def export_for_d3(graph_data)
        {
          nodes: graph_data[:nodes].map do |node|
            {
              id: node[:id],
              name: node[:label],
              group: node[:type],
              **node[:data]
            }
          end,
          links: graph_data[:edges].map do |edge|
            {
              source: edge[:source],
              target: edge[:target],
              type: edge[:type],
              value: edge[:data][:strength] || 1
            }
          end
        }
      end

      def export_for_vis_js(graph_data)
        {
          nodes: graph_data[:nodes].map do |node|
            {
              id: node[:id],
              label: node[:label],
              group: node[:type],
              title: generate_node_tooltip(node),
              **convert_style_to_vis(node[:style])
            }
          end,
          edges: graph_data[:edges].map do |edge|
            {
              from: edge[:source],
              to: edge[:target],
              label: edge[:type],
              **convert_style_to_vis(edge[:style])
            }
          end
        }
      end

      def export_for_graphviz(graph_data)
        dot_content = "digraph dependencies {\n"
        dot_content += "  rankdir=TB;\n"
        dot_content += "  node [shape=ellipse];\n\n"

        # 노드 정의
        graph_data[:nodes].each do |node|
          dot_content += "  \"#{node[:id]}\" [label=\"#{node[:label]}\"];\n"
        end

        dot_content += "\n"

        # 엣지 정의
        graph_data[:edges].each do |edge|
          dot_content += "  \"#{edge[:source]}\" -> \"#{edge[:target]}\";\n"
        end

        dot_content += "}\n"

        dot_content
      end

      # 헬퍼 메소드들

      def build_dependency_matrix(detailed_dependencies)
        # 의존성 매트릭스 구성 (간단한 예시)
        {}
      end

      def extract_cell_metadata(formula_analysis)
        {}
      end

      def identify_cross_sheet_dependencies(detailed_dependencies)
        []
      end

      def extract_cell_dependencies(formula)
        # 수식에서 셀 참조 추출 (간단한 정규식 사용)
        formula.scan(/[A-Z]+\d+/).uniq
      end

      def determine_cell_type(formula)
        if formula.blank?
          :data_cell
        elsif formula.match?(/[A-Z]+\d+:[A-Z]+\d+/)
          :range
        elsif formula.include?("!")
          :external_reference
        else
          :formula_cell
        end
      end

      def calculate_cell_complexity(formula)
        return 0.0 if formula.blank?

        # 간단한 복잡도 계산
        complexity = formula.length / 10.0
        complexity += formula.scan(/[A-Z]+\s*\(/).length * 0.5
        complexity += formula.count("(") * 0.3

        complexity.round(2)
      end

      def extract_sheet_name(cell_id)
        cell_id.include?("!") ? cell_id.split("!").first : "Sheet1"
      end

      def extract_subgraph_dependencies(full_analysis, focus_cell, depth)
        # BFS를 사용해서 지정된 깊이까지 탐색
        visited = Set.new
        queue = [ [ focus_cell, 0 ] ]
        subgraph_cells = Set.new

        dependencies = full_analysis[:detailed_dependencies][:dependencies]
        dependents = full_analysis[:detailed_dependencies][:dependents]

        while queue.any?
          current_cell, current_depth = queue.shift
          next if visited.include?(current_cell) || current_depth > depth

          visited.add(current_cell)
          subgraph_cells.add(current_cell)

          # 의존하는 셀들 추가
          (dependencies[current_cell] || []).each do |dep_cell|
            queue << [ dep_cell, current_depth + 1 ] unless visited.include?(dep_cell)
          end

          # 의존받는 셀들 추가
          (dependents[current_cell] || []).each do |dep_cell|
            queue << [ dep_cell, current_depth + 1 ] unless visited.include?(dep_cell)
          end
        end

        # 서브그래프 데이터 구성
        subgraph_data = {
          detailed_dependencies: {
            cells: {},
            dependencies: {},
            dependents: {}
          }
        }

        subgraph_cells.each do |cell|
          if full_analysis[:detailed_dependencies][:cells][cell]
            subgraph_data[:detailed_dependencies][:cells][cell] = full_analysis[:detailed_dependencies][:cells][cell]
          end

          if dependencies[cell]
            subgraph_data[:detailed_dependencies][:dependencies][cell] = dependencies[cell] & subgraph_cells.to_a
          end

          if dependents[cell]
            subgraph_data[:detailed_dependencies][:dependents][cell] = dependents[cell] & subgraph_cells.to_a
          end
        end

        subgraph_data
      end

      def generate_node_label(cell_id, cell_info)
        if cell_info[:formula].present?
          "#{cell_id}\n#{cell_info[:formula][0..20]}..."
        else
          cell_id
        end
      end

      def generate_node_style(cell_type, complexity)
        base_style = NODE_TYPES[cell_type] || NODE_TYPES[:formula_cell]

        style = {
          background_color: base_style[:color],
          shape: base_style[:shape],
          border_width: 2,
          border_color: "#333333",
          font_size: 12,
          text_valign: "center",
          text_halign: "center"
        }

        # 복잡도에 따른 크기 조정
        style[:width] = [ 30 + complexity * 5, 100 ].min
        style[:height] = [ 30 + complexity * 3, 60 ].min

        style
      end

      def generate_node_position(cell_id, options)
        # 그리드 기반 초기 위치 (실제로는 셀 위치 정보 활용)
        if cell_id.match(/([A-Z]+)(\d+)/)
          col = $1
          row = $2.to_i

          col_num = col.bytes.sum - 64  # A=1, B=2, ...

          {
            x: col_num * 100,
            y: row * 50
          }
        else
          {
            x: rand(500),
            y: rand(500)
          }
        end
      end

      def determine_edge_type(source_cell, target_cell, dependency_analysis)
        # 시트 간 참조인지 확인
        source_sheet = extract_sheet_name(source_cell)
        target_sheet = extract_sheet_name(target_cell)

        if source_sheet != target_sheet
          :cross_sheet
        else
          :direct_dependency
        end
      end

      def calculate_dependency_strength(source_cell, target_cell, dependency_analysis)
        # 의존성 강도 계산 (간단한 예시)
        1.0
      end

      def generate_edge_style(edge_type)
        base_style = EDGE_TYPES[edge_type] || EDGE_TYPES[:direct_dependency]

        {
          line_color: base_style[:color],
          width: base_style[:width],
          line_style: base_style[:style],
          target_arrow_shape: base_style[:arrow],
          curve_style: "bezier"
        }
      end

      def find_circular_path(current_cell, immediate_deps, all_dependencies, path)
        return path + [ current_cell ] if path.include?(current_cell)
        return [] if path.length > 10  # 무한 루프 방지

        immediate_deps.each do |dep_cell|
          next_deps = all_dependencies[dep_cell] || []
          result = find_circular_path(dep_cell, next_deps, all_dependencies, path + [ current_cell ])
          return result if result.any?
        end

        []
      end

      def calculate_circular_reference_severity(path)
        case path.length
        when 0..2 then "low"
        when 3..5 then "medium"
        else "high"
        end
      end

      def assess_circular_reference_impact(path, dependency_analysis)
        # 순환 참조 영향도 평가
        {
          affected_calculations: path.length * 2,
          performance_impact: "medium",
          data_integrity_risk: "high"
        }
      end

      def identify_input_nodes(nodes, edges)
        # 들어오는 엣지가 없는 노드들
        target_nodes = Set.new(edges.map { |e| e[:target] })
        nodes.reject { |n| target_nodes.include?(n[:id]) }
      end

      def identify_output_nodes(nodes, edges)
        # 나가는 엣지가 없는 노드들
        source_nodes = Set.new(edges.map { |e| e[:source] })
        nodes.reject { |n| source_nodes.include?(n[:id]) }
      end

      def find_longest_path(start_node, end_node, edges)
        # 간단한 경로 탐색 (실제로는 더 정교한 알고리즘 필요)
        [ start_node[:id], end_node[:id] ]
      end

      def calculate_path_impact_score(path, nodes)
        # 경로의 영향도 점수 계산
        path.length * 10.0
      end

      def calculate_graph_density(nodes, edges)
        return 0.0 if nodes.length < 2

        max_edges = nodes.length * (nodes.length - 1)
        (edges.length.to_f / max_edges * 100).round(2)
      end

      def calculate_average_degree(nodes, edges)
        return 0.0 if nodes.empty?

        (edges.length * 2.0 / nodes.length).round(2)
      end

      def calculate_max_degree(nodes, edges)
        degree_counts = Hash.new(0)

        edges.each do |edge|
          degree_counts[edge[:source]] += 1
          degree_counts[edge[:target]] += 1
        end

        degree_counts.values.max || 0
      end

      def calculate_max_dependency_depth(graph_data)
        # 최대 의존성 깊이 계산
        graph_data[:critical_paths].map { |path| path[:length] }.max || 0
      end

      def calculate_node_type_distribution(nodes)
        distribution = Hash.new(0)
        nodes.each { |node| distribution[node[:type]] += 1 }
        distribution
      end

      def calculate_edge_type_distribution(edges)
        distribution = Hash.new(0)
        edges.each { |edge| distribution[edge[:type]] += 1 }
        distribution
      end

      def calculate_complexity_distribution(nodes)
        ranges = { low: 0, medium: 0, high: 0 }

        nodes.each do |node|
          complexity = node[:data][:complexity] || 0
          case complexity
          when 0...3.0 then ranges[:low] += 1
          when 3.0...7.0 then ranges[:medium] += 1
          else ranges[:high] += 1
          end
        end

        ranges
      end

      def generate_navigation_info(focus_cell, dependency_data)
        {
          current_focus: focus_cell,
          available_directions: [ "up", "down", "left", "right" ],
          related_cells: dependency_data[:detailed_dependencies][:dependencies][focus_cell] || []
        }
      end

      def generate_expansion_hints(dependency_data, current_depth)
        # 더 탐색할 수 있는 노드들
        []
      end

      def group_nodes_by_sheet(nodes)
        nodes.group_by { |node| node[:data][:sheet] }
      end

      def group_nodes_by_complexity(nodes)
        nodes.group_by do |node|
          complexity = node[:data][:complexity] || 0
          case complexity
          when 0...3.0 then "Low"
          when 3.0...7.0 then "Medium"
          else "High"
          end
        end
      end

      def generate_cluster_color(index)
        colors = [ "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#DDA0DD" ]
        colors[index % colors.length]
      end

      def generate_complexity_color(level)
        case level
        when "Low" then "#4CAF50"
        when "Medium" then "#FF9800"
        when "High" then "#F44336"
        else "#9E9E9E"
        end
      end

      def generate_cytoscape_stylesheet
        [
          {
            selector: "node",
            style: {
              'background-color': "data(background_color)",
              'label': "data(label)",
              'width': "data(width)",
              'height': "data(height)",
              'font-size': 12,
              'text-valign': "center",
              'text-halign': "center"
            }
          },
          {
            selector: "edge",
            style: {
              'width': "data(width)",
              'line-color': "data(line_color)",
              'target-arrow-color': "data(line_color)",
              'target-arrow-shape': "triangle",
              'curve-style': "bezier"
            }
          }
        ]
      end

      def generate_node_tooltip(node)
        "#{node[:id]}: #{node[:data][:formula]}"
      end

      def convert_style_to_vis(style)
        # Cytoscape 스타일을 vis.js 형식으로 변환
        {
          color: style[:background_color],
          size: style[:width] || 30
        }
      end

      # 그래프 메트릭 계산 메소드들 (상세 구현은 복잡한 그래프 알고리즘 필요)

      def calculate_dependency_depth(graph_data)
        5 # 예시 값
      end

      def calculate_fanout_distribution(nodes, edges)
        {} # 실제 구현 필요
      end

      def calculate_fanin_distribution(nodes, edges)
        {} # 실제 구현 필요
      end

      def identify_dependency_chains(graph_data)
        [] # 실제 구현 필요
      end

      def calculate_cyclomatic_complexity(nodes, edges)
        edges.length - nodes.length + 1
      end

      def count_connected_components(graph_data)
        1 # 간단한 예시
      end

      def calculate_clustering_coefficient(graph_data)
        0.5 # 예시 값
      end

      def calculate_degree_centrality(nodes, edges)
        {} # 실제 구현 필요
      end

      def calculate_betweenness_centrality(graph_data)
        {} # 실제 구현 필요
      end

      def calculate_closeness_centrality(graph_data)
        {} # 실제 구현 필요
      end

      def calculate_shortest_paths(graph_data)
        {} # 실제 구현 필요
      end

      def calculate_graph_diameter(graph_data)
        5 # 예시 값
      end

      def calculate_average_path_length(graph_data)
        2.5 # 예시 값
      end
    end
  end
end
